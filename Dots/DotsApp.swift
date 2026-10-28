import SwiftUI
import CloudKit
import WidgetKit

#if !DOTS_RENDER
@main
struct DotsApp: App {
    @UIApplicationDelegateAdaptor(DotsAppDelegate.self) private var delegate
    @State private var model = CircleModel()
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--capture-store") { StoreCapture() }
            else { DotsRoot().environment(model) }
            #else
            DotsRoot().environment(model)
            #endif
        }
    }
}
#endif

final class DotsAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = DotsSceneDelegate.self
        return configuration
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { completion(.noData); return }
        Task { @MainActor in
            do {
                let store = CircleStore()
                var state = try store.load()
                guard state.cloudEnabled else { completion(.noData); return }
                let friends = try await CloudCircle().friends()
                state = try store.load()
                guard state.cloudEnabled else { completion(.noData); return }
                state.receiveFriends(friends, at: Date())
                state.lastSyncedAt = Date()
                try store.save(state)
                WidgetCenter.shared.reloadTimelines(ofKind: DotsConfig.widgetKind)
                NotificationCenter.default.post(name: .dotsRefresh, object: nil)
                completion(.newData)
            } catch { completion(.failed) }
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
