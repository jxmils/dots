import SwiftUI
import CloudKit
import UIKit

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let model: CircleModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: model.cloud.container)
        controller.availablePermissions = [.allowPrivate, .allowReadOnly]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let model: CircleModel
        init(model: CircleModel) { self.model = model }
        func itemTitle(for csc: UICloudSharingController) -> String? { "Your Dotlings companion" }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            model.error = error.localizedDescription
        }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { Task { await model.refresh() } }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { Task { await model.refresh() } }
    }
}
