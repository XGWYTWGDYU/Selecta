import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    func configure() { center.delegate = self }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .badge, .sound]) }
    func status() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    static func content(for result: OCRText) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = result.engine + " OCR结果"
        content.body = result.text
        content.sound = .default
        return content
    }
    func postOCR(_ result: OCRText) async throws {
        var permission = await status()
        if permission == .notDetermined {
            _ = try await requestAuthorization()
            permission = await status()
        }
        guard permission == .authorized || permission == .provisional else {
            throw SelectaError.message("已识别并复制文字，但通知权限未开启。请在 Selecta 设置 → 权限中允许通知。")
        }
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: Self.content(for: result), trigger: nil))
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
