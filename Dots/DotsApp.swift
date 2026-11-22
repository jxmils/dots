import SwiftUI
import CloudKit
import WidgetKit
import UserNotifications

#if !DOTS_RENDER
@main
struct DotsApp: App {
    @UIApplicationDelegateAdaptor(DotsAppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--capture-store") { StoreCapture() }
            else { DotsRoot().environment(delegate.model) }
            #else
            DotsRoot().environment(delegate.model)
            #endif
        }
    }
}
#endif

final class DotsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    lazy var model = CircleModel()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.content.userInfo["dotlingsMood"] as? Bool == true ? [.banner, .list] : []
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.userInfo["dotlingsMood"] as? Bool == true {
            await UIApplication.shared.open(URL(string: "dots://friends")!)
        }
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = DotsSceneDelegate.self
        return configuration
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let push = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let id = push.subscriptionID,
              id == "dots-friends" || id == "dots-private" || id.hasPrefix("dots-mood-") else { completion(.noData); return }
        Task { @MainActor in
            guard model.state.sharingEnabled else { completion(.noData); return }
            let before = model.state.friends
            await model.refresh(waitForCompletion: true)
            completion(before != model.state.friends ? .newData : model.syncIssue == nil ? .noData : .failed)
        }
    }
}

final class DotsSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        NotificationCenter.default.post(name: .dotsShareAccepted, object: metadata)
    }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let metadata = options.cloudKitShareMetadata {
            // SwiftUI's root subscribes after the scene connects. Retain the invitation until it is ready.
            PendingInvitation.metadata = metadata
        }
    }
}

@MainActor enum PendingInvitation { static var metadata: CKShare.Metadata? }
