import SwiftUI

struct HatchingView: View {
    @Environment(CircleModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var free = false
    var onFinish: (() -> Void)?
    var previewRevealed: CompanionKind?
    @State private var owner = ""
    @State private var petName = ""
    @State private var warmth: Double = 0
    @State private var taps = 0
    @State private var lastPoint: CGPoint?
    @State private var lastHaptic = Date.distantPast
    @State private var shellTilt = 0.0
    @State private var shakeTask: Task<Void, Never>?
    @State private var strokeDistance: CGFloat = 0
    @State private var revealed: CompanionKind?
    @FocusState private var nameFocused: Bool

    private var ready: Bool { warmth >= 1 }
    private var hatchOwner: String { model.preview ? model.state.companion?.ownerName ?? "Alex" : owner }
    var body: some View {
        Group {
            if model.preview { content }
            else { ScrollView { content }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively) }
        }
        .foregroundStyle(DotsStyle.ink).background(DotsStyle.paper.ignoresSafeArea())
        .interactiveDismissDisabled(revealed != nil)
        .onDisappear { shakeTask?.cancel() }
    }
    private var content: some View {
        VStack(spacing: 24) {
            HStack {
                Text("dotlings").font(DotsStyle.brand(28))
                Spacer()
                if !free && revealed == nil { Button("Done") { dismiss() }.font(DotsStyle.round(14, weight: .semibold)) }
            }
            Spacer(minLength: 0)
            if let revealed = revealed ?? (model.preview ? previewRevealed : nil) {
                Text("Someone small\nfound you.").font(DotsStyle.round(34, weight: .bold)).multilineTextAlignment(.center)
                CompanionView(mood: .happy, kind: revealed, animate: true).frame(width: 280, height: 280)
                    .transition(.scale(scale: reduceMotion ? 1 : 0.65).combined(with: .opacity))
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
                Text(free ? "A little beginning." : "A little thank you.")
                    .font(DotsStyle.round(32, weight: .bold)).multilineTextAlignment(.center)
                Text(free ? "Your first companion is waiting inside." : "You showed up for yourself. Someone new is waiting.")
                    .font(DotsStyle.round(14)).foregroundStyle(DotsStyle.muted).multilineTextAlignment(.center)
                ZStack {
                    Circle().fill(DotsStyle.lilac.opacity(0.2 + warmth * 0.6)).frame(width: 260, height: 260)
                    EggShell(warmth: warmth, cracks: taps).frame(width: 174, height: 214)
                        .rotationEffect(.degrees(reduceMotion ? 0 : shellTilt))
                        .offset(x: reduceMotion ? 0 : shellTilt * 0.7, y: reduceMotion ? 0 : -abs(shellTilt) * 0.5)
                }.frame(height: 282)
                    .contentShape(Circle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            nameFocused = false
                            if let lastPoint {
                                let distance = hypot(value.location.x - lastPoint.x, value.location.y - lastPoint.y)
                                strokeDistance += distance
                                warm(Double(distance) / 1100)
                            }
                            lastPoint = value.location
                        }
                        .onEnded { value in
                            lastPoint = nil
                            if strokeDistance < 10 { tapEgg() }
                            strokeDistance = 0
                        })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ready ? "Warm egg, \(taps) of 3 taps to hatch" : "Egg, \(Int(warmth * 100)) percent warmed")
                    .accessibilityAction(named: ready ? "Tap to hatch" : "Warm the shell") { tapEgg() }
                VStack(spacing: 10) {
                    DotsProgress(value: warmth, label: "Egg warmth").frame(width: 160)
                    Text(ready ? "Three gentle taps. Someone's waking up." : "Rub the shell. A little warmth works wonders.")
                        .font(DotsStyle.round(13)).foregroundStyle(DotsStyle.muted).multilineTextAlignment(.center)
                }
                if free {
                    if model.preview {
                        Text(hatchOwner).font(DotsStyle.round(16)).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    } else {
                        TextField("Your first name", text: $owner).textContentType(.givenName)
                            .font(DotsStyle.round(16)).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                            .accessibilityLabel("Your first name").focused($nameFocused).submitLabel(.done).onSubmit { nameFocused = false }
                    }
                }
                Button { tapEgg() } label: {
                    pill(ready ? "Tap the shell · \(taps)/3" : "Warm the shell", icon: ready ? "sparkles" : "hands.sparkles.fill")
                }.disabled(free && hatchOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.storageAvailable)
                Text(free ? "One free hatch. No purchase needed." : "Every milestone egg is a creature you haven't met.")
                    .font(DotsStyle.round(11)).foregroundStyle(DotsStyle.muted).multilineTextAlignment(.center)
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
    private func shakeShell() {
        guard Date().timeIntervalSince(lastHaptic) > 0.18 else { return }
        lastHaptic = Date()
        shakeTask?.cancel()
        TouchFeedback.shell(warmth: warmth)
        shakeTask = Task { @MainActor in
            for tilt in [7.0, -6.0, 4.0, -2.0, 0.0] {
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.055)) {
                    shellTilt = tilt * (0.5 + warmth * 0.5)
                }
                try? await Task.sleep(for: .milliseconds(55))
            }
        }
    }
    private func warm(_ amount: Double) {
        guard amount > 0, !free || !hatchOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { warmth = min(1, warmth + amount) }
        shakeShell()
    }

    private func tapEgg() {
        guard !free || !hatchOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if !ready { warm(0.25); return }
        taps += 1
        shakeShell()
        if taps >= 3 {
            if let kind = model.hatch(owner: free ? hatchOwner : nil) {
                shakeTask?.cancel()
                shellTilt = 0
                petName = kind.defaultName
                withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.7)) { revealed = kind }
                TouchFeedback.hatch()
            } else { taps = 2 }
        }
    }
}

struct EggShell: View {
    var warmth: Double
    var cracks: Int
    var body: some View {
        ZStack {
            Ellipse().fill(LinearGradient(colors: [.white, DotsStyle.lilac.opacity(0.6 + warmth * 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Ellipse().stroke(.white, lineWidth: 2))
                .shadow(color: DotsStyle.plum.opacity(0.12), radius: 22, y: 12)
            ForEach(0..<7) { index in
                Circle().fill(DotsStyle.plum.opacity(0.12)).frame(width: CGFloat(6 + index % 3 * 4), height: CGFloat(6 + index % 3 * 4))
                    .offset(x: CGFloat((index * 31) % 95 - 47), y: CGFloat((index * 47) % 140 - 70))
            }
            if cracks > 0 {
                Path { path in
                    path.move(to: CGPoint(x: 80, y: 45)); path.addLines([CGPoint(x: 65, y: 76), CGPoint(x: 91, y: 95), CGPoint(x: 73, y: 124)])
                    if cracks > 1 { path.addLines([CGPoint(x: 105, y: 143), CGPoint(x: 87, y: 178)]) }
                }.stroke(DotsStyle.plum.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            Image(systemName: "heart.fill").font(.system(size: 24)).foregroundStyle(.white.opacity(warmth)).offset(y: 12)
        }
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
