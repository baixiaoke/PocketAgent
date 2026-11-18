import Foundation
import UIKit
import Vision
import CoreLocation

// MARK: - 网页正文提取
enum WebText {
    /// 从 HTML 里抠正文：去脚本样式、去标签、压空白。够用，不引第三方。
    static func extract(_ html: String) -> String {
        var t = html
        let drop = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<nav[^>]*>[\\s\\S]*?</nav>",
            "<header[^>]*>[\\s\\S]*?</header>",
            "<footer[^>]*>[\\s\\S]*?</footer>",
            "<aside[^>]*>[\\s\\S]*?</aside>",
            "<!--[\\s\\S]*?-->"
        ]
        for p in drop {
            t = t.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }
        t = t.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
                        "&quot;": "\"", "&#39;": "'", "&mdash;": "—", "&hellip;": "…"]
        for (k, v) in entities { t = t.replacingOccurrences(of: k, with: v) }
        t = t.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 定位
final class LocationBox: NSObject, CLLocationManagerDelegate {
    static let shared = LocationBox()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func current() async -> CLLocation? {
        manager.requestWhenInUseAuthorization()
        return await withCheckedContinuation { c in
            continuation = c
            manager.requestLocation()
            // 5 秒兜底
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.finish(nil)
            }
        }
    }

    private func finish(_ loc: CLLocation?) {
        continuation?.resume(returning: loc)
        continuation = nil
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        finish(locs.first)
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    /// 反查城市名
    func placeName(_ loc: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        guard let marks = try? await geocoder.reverseGeocodeLocation(loc), let p = marks.first else {
            return nil
        }
        return [p.locality, p.subLocality, p.administrativeArea]
            .compactMap { $0 }
            .first
    }
}

// MARK: - 天气（wttr.in，免费无 key）
enum WeatherBox {
    static func fetch(lat: Double, lon: Double) async -> String {
        let url = "https://wttr.in/\(String(format: "%.2f", lat)),\(String(format: "%.2f", lon))?format=%25l:+%25c+%25t+(%25f)+%25w+%25h&lang=zh"
        guard let u = URL(string: url) else { return "天气地址拼装失败" }
        var req = URLRequest(url: u)
        req.timeoutInterval = 15
        req.setValue("curl/8", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.isEmpty ? "没拿到天气数据" : text
        } catch {
            return "天气查询失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 图片 OCR（本地 Vision，不联网）
enum OCRBox {
    static func recognize(_ image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "图片读取失败" }
        return await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) }
                catch { cont.resume(returning: "识别失败：\(error.localizedDescription)") }
            }
        }
    }
}

// MARK: - 用量统计
final class UsageMeter: ObservableObject {
    static let shared = UsageMeter()

    @Published private(set) var promptTokens = 0
    @Published private(set) var completionTokens = 0
    @Published private(set) var turns = 0

    private init() {
        let d = UserDefaults.standard
        promptTokens = d.integer(forKey: "usage.prompt")
        completionTokens = d.integer(forKey: "usage.completion")
        turns = d.integer(forKey: "usage.turns")
    }

    func add(prompt: Int, completion: Int) {
        promptTokens += prompt
        completionTokens += completion
        turns += 1
        let d = UserDefaults.standard
        d.set(promptTokens, forKey: "usage.prompt")
        d.set(completionTokens, forKey: "usage.completion")
        d.set(turns, forKey: "usage.turns")
    }

    func reset() {
        promptTokens = 0; completionTokens = 0; turns = 0
        let d = UserDefaults.standard
        d.set(0, forKey: "usage.prompt"); d.set(0, forKey: "usage.completion"); d.set(0, forKey: "usage.turns")
    }

    /// 按 DeepSeek 的公开价粗估（元/百万 token）
    var estimatedCost: Double {
        Double(promptTokens) / 1_000_000 * 2.0 + Double(completionTokens) / 1_000_000 * 8.0
    }

    var summary: String {
        "\(turns) 轮 · 输入 \(promptTokens) / 输出 \(completionTokens) tokens · 约 ¥\(String(format: "%.2f", estimatedCost))"
    }
}
