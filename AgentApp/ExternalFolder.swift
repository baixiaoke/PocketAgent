import Foundation
import SwiftUI

/// 用户通过「文件」选择器授权给 App 的一个外部文件夹。
/// iOS 的规矩：用户选一次 → 存 security-scoped bookmark → 之后就能长期读写，
/// 不需要每次弹框，也不需要越狱。这是沙盒内能做到的最大权限扩展。
final class ExternalFolder: ObservableObject {
    static let shared = ExternalFolder()

    @Published private(set) var name: String?
    @Published private(set) var path: String?

    private let key = "pa.externalFolderBookmark"
    private var rootURL: URL?
    private var accessing = false

    private init() { restore() }

    var root: URL? { rootURL }

    /// 由 .fileImporter 选中的文件夹 URL 调进来
    func set(_ url: URL) {
        stopAccess()
        do {
            let data = try url.bookmarkData(options: [],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            UserDefaults.standard.set(data, forKey: key)
            adopt(url)
        } catch {
            name = nil
            path = nil
        }
    }

    func clear() {
        stopAccess()
        UserDefaults.standard.removeObject(forKey: key)
        rootURL = nil
        name = nil
        path = nil
    }

    private func adopt(_ url: URL) {
        accessing = url.startAccessingSecurityScopedResource()
        rootURL = url
        name = url.lastPathComponent
        path = url.path
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return }
        adopt(url)
        if stale, let fresh = try? url.bookmarkData(options: [],
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: key)
        }
    }

    private func stopAccess() {
        if accessing { rootURL?.stopAccessingSecurityScopedResource() }
        accessing = false
    }

    /// 把工具传进来的相对路径解析到授权文件夹内，越界返回 nil
    func resolve(_ relative: String) -> URL? {
        guard let root = rootURL else { return nil }
        let trimmed = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = root.standardizedFileURL
        let target: URL
        if trimmed.isEmpty || trimmed == "." || trimmed == "/" {
            target = base
        } else {
            target = base.appendingPathComponent(trimmed).standardizedFileURL
        }
        guard target.path == base.path || target.path.hasPrefix(base.path + "/") else { return nil }
        return target
    }

    func relativePath(_ url: URL) -> String {
        guard let root = rootURL else { return url.lastPathComponent }
        let base = root.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        return p == base ? "." : String(p.dropFirst(base.count + 1))
    }
}
