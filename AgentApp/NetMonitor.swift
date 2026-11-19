import Foundation
import Network
import SwiftUI

/// 系统原生的网络判断：不需要第三方库，也不依赖任何服务器
final class NetMonitor: ObservableObject {
    static let shared = NetMonitor()

    @Published private(set) var online = true
    @Published private(set) var kind = "未知"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "net.monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status = path.status == .satisfied
            var k = "离线"
            if status {
                if path.usesInterfaceType(.wifi) { k = "Wi-Fi" }
                else if path.usesInterfaceType(.cellular) { k = "蜂窝" }
                else if path.usesInterfaceType(.wiredEthernet) { k = "有线" }
                else { k = "已连接" }
            }
            DispatchQueue.main.async {
                self?.online = status
                self?.kind = k
            }
        }
        monitor.start(queue: queue)
    }

    var summary: String { online ? "在线（\(kind)）" : "离线" }

    /// 探测某个地址是否可达（只看能不能连上，不看内容）
    static func reachable(_ raw: String, timeout: TimeInterval = 6) async -> (Bool, String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/chat/completions") { s = String(s.dropLast("/chat/completions".count)) }
        guard let url = URL(string: s + "/models") else { return (false, "地址不合法") }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return (false, "无 HTTP 响应") }
            // 401/403 也说明服务是通的，只是没带 Key
            if (200..<500).contains(http.statusCode) {
                return (true, "可达（HTTP \(http.statusCode)）")
            }
            return (false, "服务端返回 HTTP \(http.statusCode)")
        } catch {
            let ns = error as NSError
            let msg: String
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: msg = "设备没有网络"
            case NSURLErrorCannotFindHost:         msg = "域名解析失败"
            case NSURLErrorCannotConnectToHost:    msg = "连不上主机（端口被墙或服务没开）"
            case NSURLErrorTimedOut:               msg = "超时（\(Int(timeout)) 秒没响应）"
            case NSURLErrorSecureConnectionFailed: msg = "TLS 握手失败"
            default:                               msg = error.localizedDescription
            }
            return (false, msg)
        }
    }
}
