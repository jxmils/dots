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
            model.error = CircleSyncMessage.text(for: error)
        }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { Task { await model.refresh() } }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { Task { await model.refresh() } }
    }
}

struct FriendInviteSheet: UIViewControllerRepresentable {
    let invite: FriendInvite
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [invite.url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ManageFriendLinks: View {
    @State private var passes: [FriendLinks.SentPass] = []
    @State private var loading = true
    @State private var issue: String?
    @State private var selected: FriendLinks.SentPass?
    var body: some View {
        List {
            if loading { ProgressView() }
            if let issue { Text(issue); Button("Try again") { Task { await reload() } } }
            if !loading && issue == nil && passes.isEmpty { Text("You haven’t sent any invitations yet.") }
            ForEach(passes) { pass in
                VStack(alignment: .leading) {
                    Text(pass.accepted ? "Connected friend" : (pass.expires < Date() ? "Expired invitation" : "Waiting for your friend"))
                    Text("Sent " + pass.created.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    Button("Turn off this link", role: .destructive) { selected = pass }
                }
            }
        }.navigationTitle("Friend links").task { await reload() }
        .confirmationDialog("Turn off this link?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), presenting: selected) { pass in
            Button("Turn off link", role: .destructive) {
                Task {
                    do { try await FriendLinks.shared.revoke(pass.id); await reload() }
                    catch { issue = LinkError.unavailable.localizedDescription }
                }
            }
        } message: { _ in Text("The person using this link will lose access to your mood.") }
    }
    private func reload() async {
        loading = true; defer { loading = false }
        do { passes = try await FriendLinks.shared.sent(); issue = nil }
        catch { issue = LinkError.unavailable.localizedDescription }
    }
}
