import Foundation
import UserNotifications
import SwiftUI

/// 让通知在前台也能弹出来（默认 iOS 会吞掉，App 开着就看不到）
final class NotificationBridge: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationBridge()

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

extension CareScheduler {

    /// 当前授权状态
    static func authStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func statusText(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "已允许"
        case .denied: return "被拒绝（要去系统设置里打开）"
        case .notDetermined: return "还没问过"
        case .provisional: return "静默推送"
        case .ephemeral: return "临时授权"
        @unknown default: return "未知"
        }
    }

    /// 已排程的问候（给自检用）
    static func pendingSummary() async -> String {
        let reqs = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let care = reqs.filter { $0.identifier.hasPrefix("care.") }
        if care.isEmpty { return "没有排程（打开开关并保存后才会排）" }
        var lines: [String] = []
        for r in care {
            if let t = r.trigger as? UNCalendarNotificationTrigger,
               let d = t.nextTriggerDate() {
                let f = DateFormatter()
                f.dateFormat = "M月d日 HH:mm"
                lines.append("\(r.identifier == "care.morning" ? "早上" : "晚上") · 下次 \(f.string(from: d))")
            } else {
                lines.append(r.identifier)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 立刻来一条测试通知（5 秒后）
    static func fireTest(name: String) async -> Bool {
        let ok = await requestPermission()
        guard ok else { return false }
        let content = UNMutableNotificationContent()
        content.title = name
        content.body = "这是一条测试通知，能看到说明通知是通的。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let req = UNNotificationRequest(identifier: "care.test.\(Int(Date().timeIntervalSince1970))",
                                        content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(req)
            return true
        } catch {
            return false
        }
    }

    /// App 启动时自检：开着就该有排程，没有就补上
    static func ensureScheduled(settings: AgentSettings) async {
        guard settings.careEnabled else { return }
        let status = await authStatus()
        if status == .notDetermined {
            _ = await requestPermission()
        }
        let reqs = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let missing = !reqs.contains { $0.identifier == "care.morning" }
            || !reqs.contains { $0.identifier == "care.evening" }
        if missing {
            reschedule(settings: settings)
        }
    }
}
