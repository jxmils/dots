import SwiftUI

struct HatchingView: View {
    @Environment(CircleModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var free = false
    var onFinish: (() -> Void)?
    var previewRevealed: CompanionKind?
    var previewStage: EggStage?
    @State private var owner = ""
    @State private var petName = ""
    @State private var ritual = HatchRitual()
    @State private var lastPoint: CGPoint?
    @State private var lastHaptic = Date.distantPast
    @State private var motionFrame: EggStage?
    @State private var ceremonyFrame: EggStage?
    @State private var shakeTask: Task<Void, Never>?
    @State private var hatchTask: Task<Void, Never>?
    @State private var pendingKind: CompanionKind?
    @State private var strokeDistance: CGFloat = 0
    @State private var revealed: CompanionKind?
    @FocusState private var nameFocused: Bool

    private var warmth: Double {
        guard model.preview, let previewStage else { return ritual.warmth }
        return previewStage == .sleeping ? 0 : previewStage == .warming ? 0.5 : 1
    }
    private var taps: Int {
        guard model.preview, let previewStage else { return ritual.cracks }
        return previewStage.rawValue < 5 ? 0 : min(3, previewStage.rawValue - 4)
    }
    private var ready: Bool { warmth >= 1 }
    private var opening: Bool { ritual.isOpening || (model.preview && (previewStage?.rawValue ?? 0) >= EggStage.gatheringLight.rawValue) }
    private var eggStage: EggStage { (model.preview ? previewStage : nil) ?? ceremonyFrame ?? motionFrame ?? ritual.stage }
    private var canInteract: Bool { model.storageAvailable && (!free || !hatchOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    private var hatchOwner: String { model.preview ? model.state.companion?.ownerName ?? "Alex" : owner }
    var body: some View {
        Group {
            if model.preview { content }
            else { ScrollView { content }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively) }
        }
        .foregroundStyle(DotsStyle.ink).background(DotsStyle.paper.ignoresSafeArea())
        .interactiveDismissDisabled(opening || revealed != nil)
        .onDisappear { shakeTask?.cancel(); hatchTask?.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                shakeTask?.cancel(); motionFrame = nil; lastPoint = nil; strokeDistance = 0
                if pendingKind != nil { completeReveal() }
            }
        }
    }
    private var content: some View {
        VStack(spacing: 24) {
            HStack {
                Text("dotlings").font(DotsStyle.brand(28))
                Spacer()
                if !free && revealed == nil && !opening { Button("Done") { dismiss() }.font(DotsStyle.round(14, weight: .semibold)) }
            }
            Spacer(minLength: 0)
            if let revealed = revealed ?? (model.preview ? previewRevealed : nil) {
                Text("Hello, little one.").font(DotsStyle.round(34, weight: .bold)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HatchPortrait(kind: revealed).transition(.opacity)
                Text("Meet \(revealed.defaultName)").font(DotsStyle.round(27, weight: .bold))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Their little name").font(DotsStyle.round(12, weight: .semibold)).foregroundStyle(DotsStyle.muted)
                    Group {
                        if model.preview { Text(revealed.defaultName).frame(maxWidth: .infinity, alignment: .leading) }
                        else {
                            TextField(revealed.defaultName, text: $petName)
                                .accessibilityLabel("Companion's name").focused($nameFocused).submitLabel(.done)
                                .onSubmit { nameFocused = false }
                        }
                    }.font(DotsStyle.round(20, weight: .semibold))
                        .padding(17).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    Text("Keep their default name or make it your own.").font(DotsStyle.round(11)).foregroundStyle(DotsStyle.muted)
                }
                Text("A little companion for all your feelings.").font(DotsStyle.round(14)).foregroundStyle(DotsStyle.muted)
                Button { finish(makePreferred: true) } label: {
                    pill(free ? "Take them home" : "Make this my Dotling", icon: "heart.fill")
                }
                if !free {
                    Button("Keep my current Dotling") { finish(makePreferred: false) }
                        .font(DotsStyle.round(14, weight: .semibold))
                }
            } else {
                Text(opening ? "Someone's almost here." : free ? "A little beginning." : "A little thank you.")
                    .font(DotsStyle.round(32, weight: .bold)).multilineTextAlignment(.center)
                Text(opening ? "This little moment is yours." : free ? "Your first companion is waiting inside." : "You showed up for yourself. Someone new is waiting.")
                    .font(DotsStyle.round(14)).foregroundStyle(DotsStyle.muted).multilineTextAlignment(.center)
                ZStack {
                    if eggStage == .nest, let pendingKind {
                        CompanionView(mood: .happy, kind: pendingKind).frame(width: 230, height: 230)
                            .offset(y: -18).transition(.opacity)
                    }
                    EggArtwork(stage: eggStage)
                }.frame(width: 320, height: 320)
                    .contentShape(Circle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard canInteract, !opening else { return }
                            nameFocused = false
                            if let lastPoint {
                                let distance = hypot(value.location.x - lastPoint.x, value.location.y - lastPoint.y)
                                strokeDistance += distance
                                warm(Double(distance) / 1100)
                            }
                            lastPoint = value.location
                        }
                        .onEnded { _ in
                            lastPoint = nil
                            if strokeDistance < 10 { tapEgg() }
                            strokeDistance = 0
                        })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(opening ? "Your Dotling is hatching" : ready ? "Warm egg, \(taps) of 3 taps to hatch" : "Egg, \(Int(warmth * 100)) percent warmed")
                    .accessibilityAction(named: ready ? "Tap to hatch" : "Warm the shell") { tapEgg() }
                VStack(spacing: 10) {
                    DotsProgress(value: warmth, label: "Egg warmth").frame(width: 160).opacity(opening ? 0 : 1)
                    Text(opening ? "Watch the shell open…" : ready ? "Three gentle taps. Someone's waking up." : "Rub the shell. A little warmth works wonders.")
                        .font(DotsStyle.round(13)).foregroundStyle(DotsStyle.muted).multilineTextAlignment(.center)
                }
                if free {
                    if model.preview {
                        Text(hatchOwner).font(DotsStyle.round(16)).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                            .opacity(opening ? 0 : 1)
                    } else {
                        TextField("Your first name", text: $owner).textContentType(.givenName)
                            .font(DotsStyle.round(16)).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                            .accessibilityLabel("Your first name").focused($nameFocused).submitLabel(.done).onSubmit { nameFocused = false }
                            .disabled(opening).opacity(opening ? 0 : 1).accessibilityHidden(opening)
                    }
                }
                Button { tapEgg() } label: {
                    pill(ready ? "Tap the shell · \(taps)/3" : "Warm the shell", icon: ready ? "sparkles" : "hands.sparkles.fill")
                }.disabled(!canInteract || opening).opacity(opening ? 0 : 1).accessibilityHidden(opening)
                Text(free ? "One free hatch. No purchase needed." : "Every milestone egg is a creature you haven't met.")
                    .font(DotsStyle.round(11)).foregroundStyle(DotsStyle.muted).multilineTextAlignment(.center).opacity(opening ? 0 : 1)
            }
            Spacer(minLength: 0)
        }
        .padding(28).frame(maxWidth: .infinity, minHeight: 740)
    }
    private func finish(makePreferred: Bool) {
        guard let revealed, model.nameCreature(revealed, pet: petName) else { return }
        if makePreferred { model.activate(revealed) }
        model.showHatch = false; dismiss(); onFinish?()
    }
    private func pill(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(DotsStyle.round(16, weight: .bold)).frame(maxWidth: .infinity).padding(19)
            .foregroundStyle(.white).background(DotsStyle.plum, in: Capsule())
    }
    private func shakeShell(force: Bool = false) {
        guard !opening, force || Date().timeIntervalSince(lastHaptic) > 0.24 else { return }
        lastHaptic = Date()
        shakeTask?.cancel()
        TouchFeedback.shell(warmth: warmth)
        guard !reduceMotion, taps == 0, warmth >= 0.7 else { motionFrame = nil; return }
        shakeTask = Task { @MainActor in
            for frame in [EggStage.stirringLeft, .awake, .stirringRight, .awake] {
                guard !Task.isCancelled else { return }
                motionFrame = frame
                try? await Task.sleep(for: .milliseconds(110))
            }
            guard !Task.isCancelled else { return }
            motionFrame = nil
        }
    }
    private func warm(_ amount: Double) {
        guard canInteract, !opening, amount > 0 else { return }
        ritual.warm(amount)
        shakeShell()
    }

    private func tapEgg() {
        guard canInteract, !opening, revealed == nil else { return }
        nameFocused = false
        guard ritual.tap() else { shakeShell(force: true); return }
        // Save the creature before its reveal so interruptions cannot lose an earned egg.
        guard let kind = model.hatch(owner: free ? hatchOwner : nil) else {
            ritual.retryOpening()
            motionFrame = nil
            return
        }
        shakeTask?.cancel(); motionFrame = nil
        pendingKind = kind
        petName = kind.defaultName
        ceremonyFrame = .gatheringLight
        hatchTask = Task { @MainActor in
            let sequence: [(EggStage, Int, CGFloat)] = reduceMotion
                ? [(.gatheringLight, 650, 0.3), (.nest, 900, 0)]
                : [(.gatheringLight, 650, 0.3), (.opening, 400, 0.45),
                   (.lifting, 500, 0.65), (.parting, 550, 0.35), (.nest, 900, 0)]
            for (stage, duration, intensity) in sequence {
                guard !Task.isCancelled else { return }
                if stage == .nest {
                    withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.45)) { ceremonyFrame = stage }
                    TouchFeedback.hatch()
                } else {
                    ceremonyFrame = stage
                    TouchFeedback.hatchBeat(intensity)
                }
                try? await Task.sleep(for: .milliseconds(duration))
            }
            guard !Task.isCancelled else { return }
            completeReveal()
        }
    }

    private func completeReveal() {
        guard let kind = pendingKind else { return }
        hatchTask?.cancel()
        revealed = kind
        pendingKind = nil
        ceremonyFrame = nil
    }
}

struct CollectionView: View {
    @Environment(CircleModel.self) private var model
    @State private var selected: CompanionKind?
    var body: some View {
        let progress = model.state.collection
        let streak = progress.currentStreak(on: CheckInDay.number(Date()))
        VStack(alignment: .leading, spacing: 22) {
            Text("Dotling collection").font(DotsStyle.round(32, weight: .bold)).padding(.top, 20)
            Text("Little by little · \(progress.owned.count) of \(CompanionKind.allCases.count)")
                .font(DotsStyle.round(14)).foregroundStyle(DotsStyle.muted)
            Text("Choose an owned companion as your profile Dotling. It's who your friends will see.")
                .font(DotsStyle.round(12)).foregroundStyle(DotsStyle.muted)
            HStack {
                stat("\(streak)", "day streak", "flame.fill")
                Spacer(); stat("\(progress.bestStreak)", "best streak", "sparkles")
                Spacer(); stat("\(progress.restoresRemaining)/3", "lifetime restores", "arrow.uturn.backward")
            }.padding(20).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 25))
            if !progress.eggs.isEmpty {
                Button { model.showHatch = true } label: {
                    HStack {
                        Image(systemName: "sparkles"); Text("\(progress.eggs.count) \(progress.eggs.count == 1 ? "egg is" : "eggs are") ready to hatch")
                        Spacer(); Image(systemName: "arrow.up.right")
                    }.font(DotsStyle.round(14, weight: .bold)).padding(19).foregroundStyle(.white).background(DotsStyle.plum, in: RoundedRectangle(cornerRadius: 22))
                }
            }
            if let next = progress.nextMilestone {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Next hatch: \(next) days").font(DotsStyle.round(16, weight: .bold))
                    DotsProgress(value: Double(min(streak, next)), total: Double(next), label: "Next companion reward")
                    Text("Choose a mood each day. \(max(0, next - streak)) more check-ins in this streak.")
                        .font(DotsStyle.round(11)).foregroundStyle(DotsStyle.muted)
                }.padding(19).background(DotsStyle.lilac.opacity(0.4), in: RoundedRectangle(cornerRadius: 22))
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 13) {
                ForEach(progress.displayOrder) { kind in
                    let owned = progress.owned.contains(kind)
                    Button { if owned { selected = kind } } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                if owned {
                                    CompanionView(mood: .happy, kind: kind)
                                } else {
                                    Color.gray.opacity(0.35)
                                        .mask(CompanionView(mood: .happy, kind: kind))
                                    Text("?").font(DotsStyle.round(36, weight: .bold))
                                        .foregroundStyle(DotsStyle.ink)
                                }
                            }.frame(height: 115)
                            HStack(spacing: 5) {
                                Text(owned ? progress.names[kind.rawValue] ?? kind.defaultName : "???").font(DotsStyle.round(14, weight: .bold)).lineLimit(1)
                                if model.state.companion?.kind == kind { Image(systemName: "heart.fill").font(.system(size: 9)) }
                                if !owned { Image(systemName: "lock.fill").font(.system(size: 10)) }
                            }
                            Text(owned ? kind.title : "Waiting in a milestone egg").font(DotsStyle.round(9)).foregroundStyle(DotsStyle.muted)
                        }.frame(maxWidth: .infinity).padding(12).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 25))
                    }.buttonStyle(.plain).disabled(!owned)
                        .accessibilityLabel(owned ? "\(kind.title), owned" : "Mystery Dotling, locked")
                }
            }
            Text("Milestones: " + CollectionProgress.milestones.map(String.init).joined(separator: ", ") + " days. Each unlocks once. Earned creatures and eggs stay yours after a missed day.")
                .font(DotsStyle.round(11)).foregroundStyle(DotsStyle.muted)
        }
        .sheet(item: $selected) { kind in
            VStack(spacing: 20) {
                CompanionView(mood: .happy, kind: kind, animate: true).frame(width: 250, height: 250)
                Text(model.state.collection.names[kind.rawValue] ?? kind.defaultName).font(DotsStyle.round(30, weight: .bold))
                Text(kind.title).font(DotsStyle.round(13)).foregroundStyle(DotsStyle.muted)
                Button { model.activate(kind); selected = nil } label: {
                    Text(model.state.companion?.kind == kind ? "This is my Dotling" : "Make this my Dotling").font(DotsStyle.round(16, weight: .bold)).padding(18).frame(maxWidth: .infinity)
                        .foregroundStyle(.white).background(DotsStyle.plum, in: Capsule())
                }.disabled(model.state.companion?.kind == kind)
                Text("Appears on your profile and in your friends' circle and widgets when shared.")
                    .font(DotsStyle.round(12)).foregroundStyle(DotsStyle.muted).multilineTextAlignment(.center)
            }.padding(30).presentationDetents([.large]).presentationBackground(DotsStyle.paper)
        }
    }
    private func stat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(DotsStyle.plum)
            Text(value).font(DotsStyle.round(24, weight: .bold))
            Text(label).font(DotsStyle.round(8)).foregroundStyle(DotsStyle.muted)
        }
    }
}

struct RestoreStreakView: View {
    @Environment(CircleModel.self) private var model
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.circle.fill").font(.system(size: 58)).foregroundStyle(DotsStyle.plum)
            Text("Life happens.").font(DotsStyle.round(30, weight: .bold))
            Text("Keep your \(model.state.collection.streak)-day streak with one of your \(model.state.collection.restoresRemaining) remaining lifetime restores?")
                .font(DotsStyle.round(17)).multilineTextAlignment(.center)
            Text("Missed days won't count toward an egg. Today's check-in adds one day. Your creatures stay yours either way.")
                .font(DotsStyle.round(13)).foregroundStyle(DotsStyle.muted).multilineTextAlignment(.center)
            Button { model.resolveRestore(use: true) } label: {
                Text("Use one restore").font(DotsStyle.round(16, weight: .bold)).padding(18).frame(maxWidth: .infinity)
                    .foregroundStyle(.white).background(DotsStyle.plum, in: Capsule())
            }.disabled(model.state.collection.restoresRemaining == 0)
            Button("Start a new streak") { model.resolveRestore(use: false) }.font(DotsStyle.round(14))
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(DotsStyle.paper)
            .presentationDetents([.large]).interactiveDismissDisabled()
            .alert("A little hiccup", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
}
