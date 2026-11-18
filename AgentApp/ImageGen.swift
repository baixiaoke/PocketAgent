import Foundation
import UIKit

/// 图片生成：走 OpenAI 兼容的 /images/generations
enum ImageGen {

    static func isConfigured(_ s: AgentSettings) -> Bool {
        !s.imageBaseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !s.imageModel.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 生成一张图，返回相对 Documents 的路径（如 images/img-xxx.png）
    static func generate(prompt: String,
                         settings: AgentSettings,
                         fallbackKey: String) async throws -> String {
        guard isConfigured(settings) else {
            throw NSError(domain: "image", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "还没配图片模型（设置 → 图片模型）"])
        }
        var base = settings.imageBaseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        if !base.hasSuffix("/images/generations") { base += "/images/generations" }
        guard let url = URL(string: base) else {
            throw NSError(domain: "image", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "图片接口地址不合法"])
        }

        let key = settings.imageAPIKey.isEmpty ? fallbackKey : settings.imageAPIKey
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": settings.imageModel,
            "prompt": prompt,
            "n": 1,
            "size": settings.imageSize,
            "response_format": "b64_json"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "image", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "图片接口 \(code)：\(msg.prefix(300))"])
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["data"] as? [[String: Any]],
              let first = list.first else {
            throw NSError(domain: "image", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "图片接口返回格式不认识"])
        }

        var imageData: Data?
        if let b64 = first["b64_json"] as? String {
            imageData = Data(base64Encoded: b64)
        }
        if imageData == nil, let u = first["url"] as? String, let iu = URL(string: u) {
            imageData = try? await URLSession.shared.data(from: iu).0
        }
        guard let img = imageData, !img.isEmpty else {
            throw NSError(domain: "image", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "没拿到图片数据"])
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "img-\(Int(Date().timeIntervalSince1970)).png"
        try img.write(to: dir.appendingPathComponent(name))

        // 顺手存一份到相册（失败不影响主流程）
        if let ui = UIImage(data: img) {
            UIImageWriteToSavedPhotosAlbum(ui, nil, nil, nil)
        }
        return "images/\(name)"
    }

    static func absolutePath(_ relative: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(relative)
    }
}
