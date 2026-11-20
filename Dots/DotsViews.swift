import SwiftUI
import CloudKit
import CoreTransferable
import UniformTypeIdentifiers

enum DotsTab: String, CaseIterable {
    case home = "Companion", friends = "My circle", collection = "Collection", widget = "Widgets"
    var icon: String {
        switch self { case .home: "heart.fill"; case .friends: "person.2.fill"; case .collection: "sparkles"; case .widget: "rectangle.inset.filled" }
    }
}

struct DotsRoot: View {
    @Environment(CircleModel.self) private var model
    @Environment(\.scenePhase) private var phase
    @State private var tab: DotsTab
    @State private var friend: Companion?
    @State private var welcoming = false
    @State private var showTestFriend = false
    @State private var testFriendCode = ""
    init(tab: DotsTab = .home) { _tab = State(initialValue: tab) }

    var body: some View {
        @Bindable var model = model
        Group {
            if model.state.companion == nil || welcoming {
                HatchingView(free: true, onFinish: { welcoming = false }).onAppear { welcoming = true }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(DotsStyle.plum).frame(width: 9, height: 9)
                            Text("dotlings").font(DotsStyle.brand(26))
                        }
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 3) {
                            guard TestFriend.available else { return }
                            if model.state.testFriendStartedAt != nil {
                                tab = .friends
                            } else {
                                testFriendCode = ""
                                showTestFriend = true
                            }
                        }
                        Spacer()
                        Button { model.showSettings = true } label: {
                            CompanionView(mood: model.state.companion?.mood ?? .calm, kind: model.state.companion?.kind ?? .lavender)
                                .frame(width: 44, height: 44).background(.white.opacity(0.7), in: Circle())
                        }.accessibilityLabel("Your profile and settings")
                    }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 4)
                    if model.preview {
                        // ImageRenderer doesn't draw UIKit-backed scroll views. Use the same content at its natural size.
                        page.fixedSize(horizontal: false, vertical: true)
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top).clipped()
                    } else {
                        ScrollView { page }
                            .scrollIndicators(.hidden)
                            .refreshable { await model.refresh() }
                    }
                    DotsTabBar(tab: $tab)
                }
            }
        }
        .foregroundStyle(DotsStyle.ink)
        .background(DotsStyle.paper.ignoresSafeArea())
        .tint(DotsStyle.plum)
        .buttonStyle(QuietPressStyle())
        .preferredColorScheme(.light)
        .sheet(isPresented: $model.showSettings) { SettingsView(onChooseDot: { model.showSettings = false; tab = .collection }) }
        .sheet(isPresented: $model.showWidgetGuide) { WidgetGuide() }
        .sheet(isPresented: $model.showHatch) { HatchingView() }
        .sheet(isPresented: $model.showRestore) { RestoreStreakView() }
        .sheet(item: $model.outgoingInvite) { invite in
            FriendInviteSheet(invite: invite)
        }
        .alert("Add this friend to your circle?", isPresented: Binding(get: { model.incomingInvite != nil && model.state.companion != nil && !welcoming }, set: { if !$0 { model.incomingInvite = nil } }), presenting: model.incomingInvite) { invite in
            Button("Add friend") { tab = .friends; Task { await model.acceptLink(invite) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("You’ll see their Dotling and latest mood. You choose whether to send an invitation back.") }
        .sheet(item: $friend) { FriendDetail(friend: $0) }
        .sheet(isPresented: $model.showSharing) {
            if let share = model.share { CloudSharingView(share: share, model: model) }
        }
        .alert("A little hiccup", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert("Add your test friend", isPresented: $showTestFriend) {
            SecureField("Owner code", text: $testFriendCode)
            Button("Cancel", role: .cancel) { testFriendCode = "" }
            Button("Add Sky") {
                if model.addTestFriend(ownerCode: testFriendCode) { tab = .friends }
                else { model.error = "Couldn't add Sky. Check your owner code and try again." }
                testFriendCode = ""
            }
        } message: {
            Text("Use your collection owner code. Sky changes mood every five seconds on this device while Dotlings is open.")
        }
        .task(id: "\(phase)-\(model.state.testFriendStartedAt?.timeIntervalSince1970 ?? -1)") {
            guard phase == .active, let start = model.state.testFriendStartedAt else { return }
            while !Task.isCancelled {
                model.tickTestFriend()
                let elapsed = max(0, Date().timeIntervalSince(start))
                let delay = TestFriend.interval - elapsed.truncatingRemainder(dividingBy: TestFriend.interval)
                do { try await Task.sleep(for: .seconds(max(0.05, delay))) } catch { return }
            }
        }
        .task {
            if let metadata = PendingInvitation.metadata {
                PendingInvitation.metadata = nil
                await model.accept(metadata)
            } else { await model.refresh() }
        }
        .task(id: "\(phase)-\(tab)-\(model.state.linkConnected)") {
            guard phase == .active, tab == .friends, model.state.linkConnected else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                await model.refresh()
            }
        }
        .onChange(of: phase) { _, value in
            if value == .active { Task { await model.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dotsShareAccepted)) { notification in
            if let metadata = notification.object as? CKShare.Metadata { Task { await model.accept(metadata) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dotsRefresh)) { _ in Task { await model.refresh() } }
        .onOpenURL { url in
            guard url.scheme == "dots" else { return }
            if let invite = FriendInvite(url: url) { model.incomingInvite = invite; tab = .friends }
            if url.host == "friends" { tab = .friends }
        }
    }
    @ViewBuilder private var page: some View {
        Group {
            switch tab {
            case .home: CompanionHome(onCircle: { tab = .friends })
            case .friends: CircleView(onFriend: { friend = $0 })
            case .collection: CollectionView()
            case .widget: WidgetSettingsView()
            }
        }.padding(.horizontal, 24).padding(.bottom, 24)
    }
}

struct DotsTabBar: View {
    @Binding var tab: DotsTab
    var body: some View {
        HStack(spacing: 0) {
            ForEach(DotsTab.allCases, id: \.self) { item in
                Button { if tab != item { tab = item } } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.icon).font(.system(size: 18, weight: .semibold))
                        Text(item.rawValue).font(DotsStyle.round(10, weight: .semibold))
                    }
                    .foregroundStyle(tab == item ? DotsStyle.plum : DotsStyle.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(tab == item ? DotsStyle.lilac.opacity(0.45) : .clear, in: RoundedRectangle(cornerRadius: 21))
                }.accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }.padding(7).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 29))
            .padding(.horizontal, 24).padding(.bottom, 8)
    }
}

struct CompanionHome: View {
    @Environment(CircleModel.self) private var model
    var onCircle: () -> Void
    var body: some View {
        if let companion = model.state.companion {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A LITTLE CLOSER").font(DotsStyle.round(10, weight: .bold)).tracking(2).foregroundStyle(DotsStyle.muted)
                    Text("Small friend.\nBig feelings.").font(DotsStyle.round(32, weight: .bold)).tracking(-1)
                }.padding(.top, 16)
                VStack(spacing: 0) {
                    ZStack {
                        Circle().fill(RadialGradient(colors: [companion.mood.color.opacity(0.36), companion.mood.color.opacity(0.12)],
                            center: .center, startRadius: 20, endRadius: 88)).frame(width: 176, height: 176)
                        Ellipse().fill(DotsStyle.plum.opacity(0.06)).frame(width: 112, height: 12).offset(y: 85).blur(radius: 10)
                        CompanionView(mood: companion.mood, kind: companion.kind, animate: true)
                            .frame(width: 218, height: 218)
                    }
                    Text(companion.petName).font(DotsStyle.round(26, weight: .bold)).padding(.top, 3)
                    HStack(spacing: 5) {
                        Text("Feeling")
                        Text(companion.mood.title.lowercased()).fontWeight(.semibold)
                    }.font(DotsStyle.round(14)).foregroundStyle(DotsStyle.muted).padding(.top, 3)
                    Spacer().frame(height: 14)
                }.frame(maxWidth: .infinity).padding(.bottom, 5)

                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text("How are you, really?").font(DotsStyle.round(18, weight: .bold))
                        Spacer()
                        if model.syncing { ProgressView().scaleEffect(0.7) }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
                        ForEach(Mood.allCases) { mood in
                            Button { model.setMood(mood) } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: mood.symbol).font(.system(size: 18, weight: .medium)).frame(height: 23)
                                        .foregroundStyle(companion.mood == mood ? DotsStyle.ink : DotsStyle.plum.opacity(0.8))
                                    Text(mood.title).font(DotsStyle.round(11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                                }.frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .foregroundStyle(DotsStyle.ink)
                                    .background(companion.mood == mood ? mood.color.opacity(0.30) : .white.opacity(0.8), in: RoundedRectangle(cornerRadius: 19))
                                    .overlay(RoundedRectangle(cornerRadius: 19).stroke(companion.mood == mood ? mood.color.opacity(0.7) : DotsStyle.plum.opacity(0.05), lineWidth: 1))
                            }
                            .accessibilityLabel("Set mood to \(mood.title)")
                            .accessibilityAddTraits(companion.mood == mood ? .isSelected : [])
                        }
                    }
                    Text(model.syncIssue != nil ? "Saved on this device. Waiting to sync." : (model.state.cloudEnabled || model.state.linkPublishing) ? "Shared with the people you've invited." : "Just for you. Invite a friend when you're ready.")
                        .font(DotsStyle.round(11)).foregroundStyle(DotsStyle.muted)
                }
                if !model.state.collection.eggs.isEmpty {
                    Button { model.showHatch = true } label: {
                        Label("Someone new is ready to hatch", systemImage: "sparkles")
                            .font(DotsStyle.round(14, weight: .bold)).frame(maxWidth: .infinity).padding(16)
                            .foregroundStyle(.white).background(DotsStyle.plum, in: RoundedRectangle(cornerRadius: 22))
                    }
                }

                Button { onCircle() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill").font(.system(size: 18)).foregroundStyle(DotsStyle.plum)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.state.friends.isEmpty ? "Make room for your people" : "Your little circle")
                                .font(DotsStyle.round(14, weight: .bold))
                            Text(model.state.friends.isEmpty ? "A small hello goes a long way." : "\(model.state.friends.count) friends, a little closer.")
                                .font(DotsStyle.round(11)).foregroundStyle(DotsStyle.muted)
                        }
                        Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 14))
                    }.padding(18).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 23))
                }.buttonStyle(QuietPressStyle())
            }
        }
    }
}

struct CircleView: View {
    @Environment(CircleModel.self) private var model
    var onFriend: (Companion) -> Void
    @State private var dragScope = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your little circle.").font(DotsStyle.round(32, weight: .bold)).tracking(-0.8)
                Text("A glimpse of how your people are feeling.").font(DotsStyle.round(14)).foregroundStyle(DotsStyle.muted)
            }.padding(.top, 20)
            if let issue = model.syncIssue {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your mood is saved on this device.").font(DotsStyle.round(14, weight: .bold))
                    Text(issue).font(DotsStyle.round(13)).foregroundStyle(DotsStyle.muted)
                    Button("Try again") { Task { await model.refresh() } }
                        .disabled(model.syncing)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
            }
            Button { Task { await model.invite() } } label: {
                HStack {
                    Image(systemName: "plus")
                    Text(model.sharing ? "Getting your invitation…" : "Invite a friend")
                    Spacer()
                    if model.sharing { ProgressView().tint(.white) } else { Image(systemName: "arrow.up.right") }
                }.font(DotsStyle.round(15, weight: .bold)).padding(19)
                    .foregroundStyle(.white).background(DotsStyle.plum, in: RoundedRectangle(cornerRadius: 22))
            }.disabled(model.sharing)
            if model.state.friends.isEmpty {
                VStack(spacing: 15) {
                    HStack(spacing: -8) {
                        CompanionView(mood: .calm).frame(width: 108, height: 108).rotationEffect(.degrees(-8))
                        CompanionView(mood: .happy, kind: .pillow).frame(width: 108, height: 108).rotationEffect(.degrees(8))
                    }.accessibilityHidden(true)
                    Text("Good things come in little circles.").font(DotsStyle.round(19, weight: .bold)).multilineTextAlignment(.center)
                    Text("Invite someone to see your mood. To see theirs, ask them to send you an invitation back.")
                        .font(DotsStyle.round(14)).foregroundStyle(DotsStyle.muted).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 22)
                    .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 30))
            } else {
                if model.state.friends.count > 1 {
                    Text("Hold and drag to rearrange.")
                        .font(DotsStyle.round(11)).foregroundStyle(DotsStyle.muted)
                }
                ForEach(model.state.sortedFriends) { friend in
                    CircleFriendCard(friend: friend, scope: dragScope, onFriend: onFriend)
                }
            }
            Label("Only people you invite can see your mood.", systemImage: "lock.fill")
                .font(DotsStyle.round(11)).foregroundStyle(DotsStyle.muted)
            if let date = model.state.lastSyncedAt {
                HStack(spacing: 3) { Text("Last checked"); Text(date, style: .relative) }
                    .font(DotsStyle.round(10)).foregroundStyle(DotsStyle.muted)
            }
        }
    }
}

// A private transfer type prevents ordinary text or unrelated drags from
// rearranging the circle. The scope also rejects drags from another window.
struct CircleFriendDrag: Codable, Transferable {
    var id: String
    var scope: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.jasonmiller.dots.friend-order", conformingTo: .data))
            .visibility(.ownProcess)
    }
}

struct CircleFriendCard: View {
    @Environment(CircleModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let friend: Companion
    let scope: UUID
    var onFriend: (Companion) -> Void
    @State private var targeted = false
    @State private var rowHeight: CGFloat = 108

    var body: some View {
        Button { onFriend(friend) } label: {
            HStack(spacing: 14) {
                CompanionView(mood: friend.mood, kind: friend.kind).frame(width: 78, height: 78)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Text(friend.ownerName).font(DotsStyle.round(18, weight: .bold))
                        if model.state.pinnedFriendID == friend.id {
                            Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(DotsStyle.plum)
                        }
                    }
                    Text(friend.mood.title).font(DotsStyle.round(13)).foregroundStyle(DotsStyle.muted)
                    Text(friend.updatedAt, style: .relative).font(DotsStyle.round(10)).foregroundStyle(DotsStyle.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(DotsStyle.muted)
            }.padding(15).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 25))
        }
        .buttonStyle(QuietPressStyle())
        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 25))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
        .overlay {
            RoundedRectangle(cornerRadius: 25)
                .strokeBorder(DotsStyle.plum.opacity(targeted ? 0.5 : 0), lineWidth: 2)
                .allowsHitTesting(false)
        }
        .draggable(CircleFriendDrag(id: friend.id, scope: scope))
        .dropDestination(for: CircleFriendDrag.self) { items, location in
            guard items.count == 1, let item = items.first, item.scope == scope else { return false }
            // Save only on release. Cancelling a drag never changes the order.
            return withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                model.moveFriend(item.id, relativeTo: friend.id, after: location.y >= rowHeight / 2)
            }
        } isTargeted: { targeted = $0 }
        .accessibilityHint("Tap to visit. Touch and hold to drag into a new position.")
        .accessibilityActions {
            let ids = model.state.sortedFriends.map(\.id)
            if let index = ids.firstIndex(of: friend.id) {
                if index > 0 {
                    Button("Move up") { model.moveFriend(friend.id, relativeTo: ids[index - 1], after: false) }
                }
                if index + 1 < ids.count {
                    Button("Move down") { model.moveFriend(friend.id, relativeTo: ids[index + 1], after: true) }
                }
            }
        }
    }
}

struct WidgetSettingsView: View {
    @Environment(CircleModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("A little hello.\nRight there.").font(DotsStyle.round(32, weight: .bold)).tracking(-0.8)
                Text("Keep someone close on your Lock Screen.").font(DotsStyle.round(14)).foregroundStyle(DotsStyle.muted)
            }.padding(.top, 20)
            VStack(spacing: 22) {
                Text("9:41").font(.system(size: 64, weight: .thin, design: .rounded))
                FriendWidgetView(friend: model.state.widgetFriend(), inline: true).frame(height: 18)
                HStack(spacing: 16) {
                    FriendWidgetView(friend: model.state.widgetFriend(), circular: true)
                        .frame(width: 65, height: 65).background(.white.opacity(0.17), in: Circle())
                    FriendWidgetView(friend: model.state.widgetFriend()).frame(width: 180, height: 65)
                }
                Text("LOCK SCREEN PREVIEW").font(DotsStyle.round(8, weight: .semibold)).tracking(2).opacity(0.6)
            }.foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 32)
                .background(LinearGradient(colors: [DotsStyle.plum, Color(red: 0.28, green: 0.30, blue: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 32))
            VStack(alignment: .leading, spacing: 12) {
                Text("Who pops up?").font(DotsStyle.round(19, weight: .bold))
                ForEach(WidgetMode.allCases) { mode in
                    Button { model.setWidget(mode, pinned: model.state.pinnedFriendID) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode == .latest ? "sparkles" : "pin.fill").frame(width: 25)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.title).font(DotsStyle.round(14, weight: .bold))
                                Text(mode == .latest ? "Whoever last shared how they feel." : "One familiar face, always there.")
                                    .font(DotsStyle.round(11)).foregroundStyle(DotsStyle.muted)
                            }
                            Spacer()
                            Image(systemName: model.state.widgetMode == mode ? "checkmark.circle.fill" : "circle")
                        }.padding(17).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 21))
                    }.buttonStyle(QuietPressStyle()).accessibilityAddTraits(model.state.widgetMode == mode ? .isSelected : [])
                }
                if model.state.widgetMode == .pinned {
                    if model.state.friends.isEmpty {
                        Text("Add a friend to choose who stays here.").font(DotsStyle.round(13)).foregroundStyle(DotsStyle.muted)
                    } else {
                        if model.preview {
                            HStack {
                                Text("Pinned friend"); Spacer()
                                Text(model.state.widgetFriend()?.ownerName ?? "Choose a friend")
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
                            }.font(DotsStyle.round(14)).padding(.vertical, 9)
                        } else {
                            Picker("Pinned friend", selection: Binding(get: { model.state.pinnedFriendID ?? "" }, set: { model.setWidget(.pinned, pinned: $0.isEmpty ? nil : $0) })) {
                                Text("Choose a friend").tag("")
                                ForEach(model.state.sortedFriends) { Text($0.ownerName).tag($0.id) }
                            }.pickerStyle(.menu)
                        }
                    }
                }
            }
            Button { model.showWidgetGuide = true } label: {
                Label("Add to my Lock Screen", systemImage: "plus").font(DotsStyle.round(15, weight: .bold))
                    .frame(maxWidth: .infinity).padding(18).foregroundStyle(.white).background(DotsStyle.plum, in: Capsule())
            }
            Text("Widgets show the latest mood received. Your iPhone decides when to refresh them; updates may take a little while.")
                .font(DotsStyle.round(11)).foregroundStyle(DotsStyle.muted)
        }
    }
}

struct FriendDetail: View {
    @Environment(CircleModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var friend: Companion
    private var currentFriend: Companion { model.state.friends.first { $0.id == friend.id } ?? friend }
    @State private var confirmRemove = false
    var body: some View {
        let friend = currentFriend
        NavigationStack {
            VStack(spacing: 18) {
                CompanionView(mood: friend.mood, kind: friend.kind, animate: true).frame(width: 240, height: 240)
                Text(friend.ownerName).font(DotsStyle.round(30, weight: .bold))
                MoodBadge(mood: friend.mood)
                Text(friend.id == TestFriend.id ? "Only on this device · changes mood every 5 seconds" : "\(friend.petName) is keeping them company.").font(DotsStyle.round(14)).foregroundStyle(DotsStyle.muted)
                HStack { Text(friend.id == TestFriend.id ? "Mood updated" : "Mood shared"); Text(friend.updatedAt, style: .relative) }.font(.caption).foregroundStyle(DotsStyle.muted)
                Button {
                    model.setWidget(.pinned, pinned: friend.id); dismiss()
                } label: {
                    Label("Pin to my widget", systemImage: "pin.fill").font(DotsStyle.round(16, weight: .bold))
                        .frame(maxWidth: .infinity).padding(18).foregroundStyle(.white).background(DotsStyle.plum, in: Capsule())
                }
                Button(friend.id == TestFriend.id ? "Remove test friend" : "Leave this friend's circle", role: .destructive) { confirmRemove = true }.font(.footnote)
                Spacer()
            }.padding(28).frame(maxWidth: .infinity).background(DotsStyle.paper)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .confirmationDialog(friend.id == TestFriend.id ? "Remove test friend?" : "Leave \(friend.ownerName)'s circle?", isPresented: $confirmRemove, titleVisibility: .visible) {
                    Button(friend.id == TestFriend.id ? "Remove test friend" : "Leave circle", role: .destructive) { Task { await model.remove(friend); if model.error == nil { dismiss() } } }
                } message: { Text(friend.id == TestFriend.id ? "This removes the test friend from this device and your widget." : "You'll stop receiving their mood. To control who sees yours, use Manage sharing in Settings.") }
        }.tint(DotsStyle.plum)
    }
}

struct ProfileDotCard: View {
    var companion: Companion
    var body: some View {
        VStack(spacing: 10) {
            CompanionView(mood: companion.mood, kind: companion.kind).frame(width: 154, height: 154)
            Text(companion.ownerName).font(DotsStyle.round(29, weight: .bold))
            Text("\(companion.petName) is your Dotling").font(DotsStyle.round(15, weight: .semibold))
            MoodBadge(mood: companion.mood)
            Text("Shown to friends when you share a mood.")
                .font(DotsStyle.round(12)).foregroundStyle(DotsStyle.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(22).background(DotsStyle.lilac.opacity(0.35), in: RoundedRectangle(cornerRadius: 28))
            .foregroundStyle(DotsStyle.ink)
    }
}

struct SettingsView: View {
    var onChooseDot: () -> Void = {}
    @Environment(CircleModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var owner = ""
    @State private var pet = ""
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let companion = model.state.companion { ProfileDotCard(companion: companion) }
                    Button("Choose my profile Dotling", action: onChooseDot)
                } header: { Text("Your preferred Dotling") }
                Section("Your little companion") {
                    TextField("Your first name", text: $owner)
                    TextField("Companion's name", text: $pet)
                    Button("Save names") { model.rename(owner: owner, pet: pet); dismiss() }
                        .disabled(owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section {
                    Button("Invite a friend") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { Task { await model.invite() } }
                    }
                        .disabled(model.sharing)
                    if model.state.linkPublishing {
                        NavigationLink("Manage friend links") { ManageFriendLinks() }
                    }
                    if model.state.cloudEnabled {
                        Button("Manage older iCloud invitations") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { Task { await model.manageAppleInvites() } }
                        }
                    }
                    Button("Check for mood updates") { Task { await model.refresh() } }.disabled(model.syncing || !model.state.sharingEnabled)
                } header: { Text("Your circle") } footer: {
                    Text("Send each friend their own link. The first person to accept can see your name, Dotling and latest mood. Unused links expire after seven days. You can turn off a link at any time.")
                }
                Section("Widgets") { Button("How to add a Lock Screen widget") { model.showSettings = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.showWidgetGuide = true } } }
                Section("Help & privacy") {
                    Link("Dotlings support", destination: URL(string: "https://github.com/jxmils/dots/blob/main/docs/support.md")!)
                    Link("Privacy policy", destination: URL(string: "https://github.com/jxmils/dots/blob/main/docs/privacy.md")!)
                }
                Section {
                    Text("Dotlings doesn't guess your feelings. You choose what to share, and you never have to check in.")
                    Text("Your companions, collection, streak and preferences are saved on this device. A recovery copy in this iPhone’s Keychain keeps your hatched pets and progress for a reinstall. If you connect friends, your current name, companion and mood are shared with the people you invite. New invitations use Firebase and work with iCloud switched off. Dotlings has no ads, analytics, chat or public directory.")
                } header: { Text("A small, private space") }
                Section {
                    Button("Delete my companion & shared mood", role: .destructive) { confirmDelete = true }
                        .disabled(model.deleting)
                    if model.deleting { ProgressView("Removing shared companion…") }
                } footer: { Text("Removes your companions, their reinstall backup, your streak, friend list and settings from this device and deletes your shared mood and friend links, including older iCloud shares. Your friends will lose access to it. Used lifetime streak restores remain used.") }
            }
            .navigationTitle("Your profile").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { owner = model.state.companion?.ownerName ?? ""; pet = model.state.companion?.petName ?? "" }
            .confirmationDialog("Delete your companion?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete companion", role: .destructive) { Task { await model.deleteCompanion() } }
            } message: { Text("This removes your shared mood and revokes your friends' access. This can't be undone.") }
        }.tint(DotsStyle.plum)
    }
}

struct WidgetGuide: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("A familiar face,\none glance away.").font(DotsStyle.round(30, weight: .bold))
                    ForEach(Array([
                        "Touch and hold your Lock Screen, then tap Customize.",
                        "Choose Lock Screen and tap the widget area below the time.",
                        "Find Dotlings and add a circular or rectangular widget.",
                        "Tap the added widget to choose your default, the latest friend mood, or a specific friend.",
                        "Close the picker and tap Done."
                    ].enumerated()), id: \.offset) { index, text in
                        HStack(alignment: .top, spacing: 15) {
                            Text("\(index + 1)").font(DotsStyle.round(16, weight: .bold)).frame(width: 31, height: 31).background(DotsStyle.lilac, in: Circle())
                            Text(text).font(DotsStyle.round(15)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("You can also add a Dotlings widget to your Home Screen from its widget gallery.").font(.footnote).foregroundStyle(DotsStyle.muted)
                }.padding(28)
            }.background(DotsStyle.paper)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(DotsStyle.plum)
    }
}
