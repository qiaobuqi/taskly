import UIKit
import UserNotifications

/// PushManager 负责 APNs 注册、设备令牌上报与前台通知展示。
/// 参考路遇的实现:启动即请求通知授权 → 注册远程通知 → 拿到 deviceToken 后,
/// 若已登录就上报到后端 `/push/device-token`(后端用同一把 APNs 密钥发推送)。
final class PushManager: NSObject {
    static let shared = PushManager()

    /// 最近一次拿到的设备令牌(hex)。登录晚于注册时,登录后可补传。
    private var pendingToken: String?

    /// 请求通知授权并注册远程通知。可在启动和登录成功后调用。
    func registerForPushNotifications() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// 收到 APNs 下发的设备令牌后调用:缓存并(若已登录)上报后端。
    @MainActor
    func handleDeviceToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        pendingToken = hex
        uploadTokenIfLoggedIn()
    }

    /// 登录成功后调用,把之前缓存的令牌补传(或触发一次注册)。
    @MainActor
    func uploadTokenIfLoggedIn() {
        guard AuthManager.shared.isLoggedIn else { return }
        guard let token = pendingToken else {
            // 还没令牌:确保已注册,令牌到达后会自动走 handleDeviceToken 上报
            registerForPushNotifications()
            return
        }
        Task {
            _ = await NetworkManager.shared.post("/push/device-token", payload: ["device_token": token])
        }
    }
}

// MARK: - 前台展示 & 点击处理
extension PushManager: UNUserNotificationCenterDelegate {
    /// App 在前台时也展示横幅 + 声音 + 角标
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    /// 用户点击通知:把自定义数据广播出去,具体页面跳转由监听方处理。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        NotificationCenter.default.post(name: .tasklyPushTapped, object: nil, userInfo: info)
        completionHandler()
    }
}

extension Notification.Name {
    /// 点击推送时发出,userInfo 含后端自定义字段(type / sender_id / message_id / task_id 等)
    static let tasklyPushTapped = Notification.Name("tasklyPushTapped")
}

// MARK: - AppDelegate(供 SwiftUI App 通过 UIApplicationDelegateAdaptor 接入)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PushManager.shared.registerForPushNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.handleDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("⚠️ APNs 注册失败: \(error.localizedDescription)")
    }
}
