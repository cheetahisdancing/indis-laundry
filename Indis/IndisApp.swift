import SwiftUI
import UserNotifications

@main
struct IndisApp: App {
    @State private var store = LaundryStore()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .tint(Theme.primary)
        }
    }
}
