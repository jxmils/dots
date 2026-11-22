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
    var previewKind: CompanionKind?
    @State private var owner = ""
    @State private var petName = ""
    @State private var ritual = HatchRitual()
    @State private var lastPoint: CGPoint?
    @State private var lastShake = Date.distantPast
    @State private var motionFrame: EggStage?
    @State private var ceremonyFrame: EggStage?
    @State private var shakeTask: Task<Void, Never>?
    @State private var hatchTask: Task<Void, Never>?
    @State private var pendingKind: CompanionKind?
    @State private var hatchFrames: [UIImage] = []
    @State private var strokeDistance: CGFloat = 0
    @State private var revealed: CompanionKind?
    @FocusState private var nameFocused: Bool

    private var warmth: Double {
        guard model.preview, let previewStage else { return ritual.warmth }
        return previewStage == .sleeping ? 0 : previewStage == .warming ? 0.5 : 1
    }
    private var taps: Int {
        guard model.preview, let previewStage else { return ritual.cracks }
        if previewStage.rawValue >= EggStage.gatheringLight.rawValue { return 3 }
        if previewStage.rawValue >= EggStage.secondCrack.rawValue { return 2 }
        return previewStage.rawValue >= EggStage.firstCrack.rawValue ? 1 : 0
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
                HatchPortrait(kind: revealed, frames: hatchFrames).transition(.opacity)
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
                EggArtwork(stage: eggStage, kind: pendingKind ?? (model.preview ? previewKind : nil), frames: hatchFrames)
                    .frame(width: 320, height: 320)
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
        guard !opening, force || Date().timeIntervalSince(lastShake) > 0.24 else { return }
        lastShake = Date()
        shakeTask?.cancel()
        guard !reduceMotion, taps == 0, warmth >= 0.7 else { motionFrame = nil; return }
        shakeTask = Task { @MainActor in
            for frame in [EggStage.stirringLeft, .warming, .stirringRight, .awake, .awakeSettled] {
                guard !Task.isCancelled else { return }
                motionFrame = frame
                try? await Task.sleep(for: .milliseconds(160))
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
        guard ritual.tap() else {
            if ritual.cracks == 2 && !reduceMotion {
                shakeTask?.cancel()
                motionFrame = .crackGrowing
                shakeTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(240))
                    guard !Task.isCancelled else { return }
                    motionFrame = nil
                }
            } else {
                shakeShell(force: true)
            }
            return
        }
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
            // Decode the awarded character's whole sequence before opening the
            // shell. Holding these frames prevents disk reads during playback.
            let loaded = await Task.detached(priority: .userInitiated) {
                CompanionArt.eggFrames(kind: kind)
            }.value
            guard !Task.isCancelled, pendingKind == kind else { return }
            hatchFrames = loaded
            guard loaded.count == EggStage.allCases.count else {
                completeReveal()
                return
            }
            for (stage, duration) in EggStage.ceremony(reduceMotion: reduceMotion) {
                guard !Task.isCancelled else { return }
                ceremonyFrame = stage
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
    @State private var showOwnerUnlock = false
    @State private var ownerCode = ""
    @State private var ownerCodeError = false
    var body: some View {
        let progress = model.availableCollection
        let streak = progress.currentStreak(on: CheckInDay.number(Date()))
        VStack(alignment: .leading, spacing: 22) {
            Text("Dotling collection").font(DotsStyle.round(32, weight: .bold)).padding(.top, 20)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 3) {
                    guard TestBuild.hasLocalTools, !progress.isComplete else { return }
                    ownerCode = ""
                    ownerCodeError = false
                    showOwnerUnlock = true
                }
            Text("\(progress.isComplete ? "Collection complete" : "Little by little") · \(progress.owned.count) of \(CompanionKind.allCases.count)")
                .font(DotsStyle.round(14)).foregroundStyle(DotsStyle.muted)
            Text("Choose an owned companion as your profile Dotling. It's who your friends will see.")
                .font(DotsStyle.round(12)).foregroundStyle(DotsStyle.muted)
            if !progress.isComplete || model.hasAllPets {
                VStack(alignment: .leading, spacing: 10) {
                    if model.hasAllPets {
                        Label("All Dotlings unlocked", systemImage: "checkmark.circle.fill")
                            .font(DotsStyle.round(16, weight: .bold))
                    } else {
                        Text("Meet every Dotling").font(DotsStyle.round(18, weight: .bold))
                        Text("Keep hatching with streaks, or unlock all \(CompanionKind.allCases.count) pets with one purchase.")
                            .font(DotsStyle.round(13)).foregroundStyle(DotsStyle.muted)
                        if let price = model.allPetsPrice {
                            Button("Unlock all Dotlings · " + price) { Task { await model.buyAllPets() } }
                                .font(DotsStyle.round(15, weight: .bold)).padding(.vertical, 8)
                        } else if model.loadingProduct {
                            ProgressView("Loading price…")
                        } else {
                            Button("Check price") { Task { await model.loadAllPetsProduct() } }
                        }
                    }
                    Button("Restore Purchases") { Task { await model.restoreAllPets() } }
                        .font(DotsStyle.round(13, weight: .semibold))
                    if model.storeBusy { ProgressView() }
                    if let message = model.storeMessage { Text(message).font(.footnote) }
                }.disabled(model.storeBusy)
                .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 22))
                .task { if !model.hasAllPets { await model.loadAllPetsProduct() } }
            }
            HStack {
                stat("\(streak)", "day streak", "flame.fill")
                Spacer(); stat("\(progress.bestStreak)", "best streak", "sparkles")
                Spacer(); stat("\(progress.restoresRemaining)/3", "lifetime restores", "arrow.uturn.backward")
            }.padding(20).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 25))
            if progress.canRestoreCurrentStreak(on: CheckInDay.number(Date())) {
                Button("Streak options") { model.showRestore = true }
                    .font(DotsStyle.round(13, weight: .semibold))
            }
            if !progress.eggs.isEmpty {
                Button { model.showHatch = true } label: {
                    HStack {
                        Image(systemName: "sparkles"); Text("\(progress.eggs.count) \(progress.eggs.count == 1 ? "egg is" : "eggs are") ready to hatch")
                        Spacer(); Image(systemName: "arrow.up.right")
                    }.font(DotsStyle.round(14, weight: .bold)).padding(19).foregroundStyle(.white).background(DotsStyle.plum, in: RoundedRectangle(cornerRadius: 22))
                }
            }
            if !progress.isComplete, let next = progress.nextMilestone {
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
                    }.buttonStyle(QuietPressStyle()).disabled(!owned)
                        .accessibilityLabel(owned ? "\(kind.title), owned" : "Mystery Dotling, locked")
                }
            }
            StreakMilestoneTimeline(progress: progress)
        }
        .sheet(isPresented: $showOwnerUnlock) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Owner collection").font(DotsStyle.round(24, weight: .bold))
                SecureField("Enter your owner code", text: $ownerCode)
                    .textContentType(nil)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                if ownerCodeError {
                    Text(model.error ?? "That code doesn't match.").font(DotsStyle.round(13))
                        .foregroundStyle(DotsStyle.muted)
                }
                Button("Unlock all Dotlings") {
                    if model.unlockOwnerCollection(code: ownerCode) {
                        ownerCode = ""
                        showOwnerUnlock = false
                    } else {
                        ownerCodeError = true
                    }
                }
                .font(DotsStyle.round(15, weight: .bold))
                .disabled(ownerCode.isEmpty)
                Button("Cancel") { showOwnerUnlock = false }
                    .font(DotsStyle.round(13))
            }
            .padding(24)
            .presentationDetents([.medium])
            .presentationBackground(DotsStyle.paper)
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

struct StreakMilestoneTimeline: View {
    let progress: CollectionProgress
    @State private var expanded = false

    var body: some View {
        let milestones = CollectionProgress.milestones
        let nextIndex = milestones.firstIndex { $0 == progress.nextMilestone } ?? milestones.count
        let start = min(max(0, nextIndex - 2), milestones.count - 4)
        let visible = expanded ? milestones : Array(milestones[start..<(start + 4)])
        VStack(alignment: .leading, spacing: 14) {
            Text("Streak milestones").font(DotsStyle.round(16, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(visible, id: \.self) { day in
                    row(day, connectsToNext: day != visible.last)
                }
            }
            Button {
                expanded.toggle()
            } label: {
                Label(expanded ? "Show fewer milestones" : "See all milestones",
                      systemImage: expanded ? "chevron.up" : "chevron.down")
                    .font(DotsStyle.round(13, weight: .semibold))
            }
        }
        .padding(19)
        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
    }

    private func row(_ day: Int, connectsToNext: Bool) -> some View {
        let earned = progress.earnedMilestones.contains(day)
        let isNext = day == progress.nextMilestone
        let status = if progress.eggs.contains(day) { "Ready to hatch" }
                     else if earned { "Reached" }
                     else if isNext { "Next" }
                     else { "Upcoming" }
        let color = earned || isNext ? DotsStyle.plum : DotsStyle.muted
        return HStack(spacing: 12) {
            Image(systemName: earned ? "checkmark.circle.fill" : isNext ? "circle.inset.filled" : "circle")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 24, height: 42)
                .foregroundStyle(color)
                .background(alignment: .bottom) {
                    if connectsToNext {
                        Rectangle().fill(DotsStyle.plum.opacity(0.15))
                            .frame(width: 1, height: 21).offset(y: 10)
                    }
                }
                .accessibilityHidden(true)
            Text("\(day) days").font(DotsStyle.round(14, weight: .semibold))
            Spacer(minLength: 6)
            Text(status).font(DotsStyle.round(12)).foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RestoreStreakView: View {
    @Environment(CircleModel.self) private var model
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.circle.fill").font(.system(size: 58)).foregroundStyle(DotsStyle.plum)
            Text("Life happens.").font(DotsStyle.round(30, weight: .bold))
            Text("Reconnect your previous \(model.state.collection.restorableStreak ?? 0)-day streak with one of your \(model.state.collection.restoresRemaining) remaining lifetime restores?")
                .font(DotsStyle.round(17)).multilineTextAlignment(.center)
            Text("Only the days you checked in count. Your recent check-ins and creatures are already saved.")
                .font(DotsStyle.round(13)).foregroundStyle(DotsStyle.muted).multilineTextAlignment(.center)
            Button { model.resolveRestore(use: true) } label: {
                Text("Use one restore").font(DotsStyle.round(16, weight: .bold)).padding(18).frame(maxWidth: .infinity)
                    .foregroundStyle(.white).background(DotsStyle.plum, in: Capsule())
            }.disabled(model.state.collection.restoresRemaining == 0)
            Button("Keep my current streak") { model.resolveRestore(use: false) }.font(DotsStyle.round(14))
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(DotsStyle.paper)
            .presentationDetents([.large])
            .alert("A little hiccup", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
}
