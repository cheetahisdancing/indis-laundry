import Foundation
import UserNotifications

/// 로컬 알림 담당. 앱이 켜져 있을 때도 배너가 보이도록 delegate 역할도 합니다.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 지정한 시각에 알림
    func schedule(id: String, title: String, body: String, at date: Date) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            guard granted, let self = self else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let interval = max(1, date.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            self.center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    /// 바로 알림
    func sendNow(title: String, body: String) {
        schedule(id: UUID().uuidString, title: title, body: body, at: Date())
    }

    func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    // 앱이 앞에 떠 있을 때도 배너 표시
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
