import SwiftUI
import UIKit

/// 一套配色
struct Palette: Identifiable, Equatable {
    let id: String
    let name: String
    let accent: UIColor
    let secondary: UIColor
    let mint: UIColor
    let amber: UIColor
    let danger: UIColor
    let voidColor: UIColor
    let deepColor: UIColor
    let panelColor: UIColor
    let bubbleTop: UIColor
    let bubbleBottom: UIColor
}

enum Palettes {
    static let all: [Palette] = [
        Palette(id: "cyan", name: "科技青",
                accent: UIColor(red: 0.22, green: 0.91, blue: 1.00, alpha: 1),
                secondary: UIColor(red: 0.55, green: 0.36, blue: 1.00, alpha: 1),
                mint: UIColor(red: 0.30, green: 0.95, blue: 0.78, alpha: 1),
                amber: UIColor(red: 1.00, green: 0.72, blue: 0.30, alpha: 1),
                danger: UIColor(red: 1.00, green: 0.38, blue: 0.42, alpha: 1),
                voidColor: UIColor(red: 0.03, green: 0.04, blue: 0.07, alpha: 1),
                deepColor: UIColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1),
                panelColor: UIColor(red: 0.09, green: 0.12, blue: 0.19, alpha: 1),
                bubbleTop: UIColor(red: 0.10, green: 0.55, blue: 0.85, alpha: 1),
                bubbleBottom: UIColor(red: 0.30, green: 0.30, blue: 0.95, alpha: 1)),

        Palette(id: "violet", name: "暗夜紫",
                accent: UIColor(red: 0.72, green: 0.48, blue: 1.00, alpha: 1),
                secondary: UIColor(red: 1.00, green: 0.42, blue: 0.72, alpha: 1),
                mint: UIColor(red: 0.62, green: 0.90, blue: 0.98, alpha: 1),
                amber: UIColor(red: 1.00, green: 0.78, blue: 0.42, alpha: 1),
                danger: UIColor(red: 1.00, green: 0.36, blue: 0.48, alpha: 1),
                voidColor: UIColor(red: 0.06, green: 0.03, blue: 0.10, alpha: 1),
                deepColor: UIColor(red: 0.10, green: 0.05, blue: 0.16, alpha: 1),
                panelColor: UIColor(red: 0.14, green: 0.09, blue: 0.21, alpha: 1),
                bubbleTop: UIColor(red: 0.45, green: 0.22, blue: 0.78, alpha: 1),
                bubbleBottom: UIColor(red: 0.85, green: 0.30, blue: 0.60, alpha: 1)),

        Palette(id: "forest", name: "森林绿",
                accent: UIColor(red: 0.37, green: 0.92, blue: 0.66, alpha: 1),
                secondary: UIColor(red: 0.16, green: 0.72, blue: 0.72, alpha: 1),
                mint: UIColor(red: 0.68, green: 0.95, blue: 0.62, alpha: 1),
                amber: UIColor(red: 0.99, green: 0.83, blue: 0.42, alpha: 1),
                danger: UIColor(red: 1.00, green: 0.42, blue: 0.38, alpha: 1),
                voidColor: UIColor(red: 0.02, green: 0.07, blue: 0.05, alpha: 1),
                deepColor: UIColor(red: 0.04, green: 0.12, blue: 0.09, alpha: 1),
                panelColor: UIColor(red: 0.08, green: 0.18, blue: 0.14, alpha: 1),
                bubbleTop: UIColor(red: 0.10, green: 0.55, blue: 0.38, alpha: 1),
                bubbleBottom: UIColor(red: 0.09, green: 0.62, blue: 0.58, alpha: 1)),

        Palette(id: "sunset", name: "暖阳橙",
                accent: UIColor(red: 1.00, green: 0.68, blue: 0.31, alpha: 1),
                secondary: UIColor(red: 1.00, green: 0.40, blue: 0.42, alpha: 1),
                mint: UIColor(red: 1.00, green: 0.87, blue: 0.52, alpha: 1),
                amber: UIColor(red: 1.00, green: 0.80, blue: 0.36, alpha: 1),
                danger: UIColor(red: 1.00, green: 0.34, blue: 0.34, alpha: 1),
                voidColor: UIColor(red: 0.09, green: 0.04, blue: 0.02, alpha: 1),
                deepColor: UIColor(red: 0.16, green: 0.07, blue: 0.03, alpha: 1),
                panelColor: UIColor(red: 0.22, green: 0.11, blue: 0.05, alpha: 1),
                bubbleTop: UIColor(red: 0.94, green: 0.48, blue: 0.20, alpha: 1),
                bubbleBottom: UIColor(red: 0.85, green: 0.28, blue: 0.35, alpha: 1)),

        Palette(id: "ice", name: "冰川蓝",
                accent: UIColor(red: 0.52, green: 0.80, blue: 1.00, alpha: 1),
                secondary: UIColor(red: 0.76, green: 0.86, blue: 1.00, alpha: 1),
                mint: UIColor(red: 0.72, green: 0.95, blue: 1.00, alpha: 1),
                amber: UIColor(red: 1.00, green: 0.85, blue: 0.55, alpha: 1),
                danger: UIColor(red: 1.00, green: 0.45, blue: 0.55, alpha: 1),
                voidColor: UIColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1),
                deepColor: UIColor(red: 0.06, green: 0.12, blue: 0.20, alpha: 1),
                panelColor: UIColor(red: 0.10, green: 0.18, blue: 0.30, alpha: 1),
                bubbleTop: UIColor(red: 0.24, green: 0.52, blue: 0.90, alpha: 1),
                bubbleBottom: UIColor(red: 0.44, green: 0.72, blue: 0.98, alpha: 1)),

        Palette(id: "mono", name: "极简黑白",
                accent: UIColor(white: 0.95, alpha: 1),
                secondary: UIColor(white: 0.60, alpha: 1),
                mint: UIColor(white: 0.80, alpha: 1),
                amber: UIColor(white: 0.88, alpha: 1),
                danger: UIColor(red: 1.00, green: 0.36, blue: 0.36, alpha: 1),
                voidColor: UIColor(white: 0.02, alpha: 1),
                deepColor: UIColor(white: 0.06, alpha: 1),
                panelColor: UIColor(white: 0.12, alpha: 1),
                bubbleTop: UIColor(white: 0.32, alpha: 1),
                bubbleBottom: UIColor(white: 0.52, alpha: 1))
    ]

    static func palette(_ id: String) -> Palette {
        all.first { $0.id == id } ?? all[0]
    }
}

/// 对外统一入口：主题 + 每页背景图
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    enum Page: String, CaseIterable, Identifiable {
        case chat = "聊天"
        case call = "通话"
        case persona = "人格"
        case memory = "记忆"
        case settings = "设置"

        var id: String { rawValue }
        var key: String {
            switch self {
            case .chat: return "chat"
            case .call: return "call"
            case .persona: return "persona"
            case .memory: return "memory"
            case .settings: return "settings"
            }
        }
    }

    @Published private(set) var paletteID: String
    @Published private(set) var backgroundRevision = 0

    private let themeKey = "pa.paletteID"

    private init() {
        paletteID = UserDefaults.standard.string(forKey: themeKey) ?? "cyan"
    }

    var palette: Palette { Palettes.palette(paletteID) }

    func select(_ id: String) {
        paletteID = id
        UserDefaults.standard.set(id, forKey: themeKey)
    }

    // MARK: 背景图
    private func folder() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("theme", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileURL(_ page: Page) -> URL {
        folder().appendingPathComponent("bg-\(page.key).jpg")
    }

    func backgroundImage(for page: Page) -> UIImage? {
        let url = fileURL(page)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    func hasBackground(_ page: Page) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(page).path)
    }

    func setBackground(_ image: UIImage, for page: Page) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: fileURL(page), options: .atomic)
        backgroundRevision += 1
    }

    func clearBackground(_ page: Page) {
        try? FileManager.default.removeItem(at: fileURL(page))
        backgroundRevision += 1
    }
}
