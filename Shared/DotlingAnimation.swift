import SwiftUI
import UIKit

enum DotlingAnimation: String, CaseIterable, Identifiable {
    case idle, moveRight, moveLeft, wave, jump, disappointed, waiting, thinking, reviewing, lookAround
    var id: String { rawValue }
    var title: String {
        switch self {
        case .idle: "Blink"; case .moveRight: "Move right"; case .moveLeft: "Move left"
        case .wave: "Wave"; case .jump: "Little hop"; case .disappointed: "Disappointed"
        case .waiting: "Waiting"; case .thinking: "Thinking"; case .reviewing: "Look closely"
        case .lookAround: "Look around"
        }
    }
    var durations: [Double] {
        switch self {
        case .idle: [1.25, 0.5, 0.07, 0.07, 0.11, 1.2]
        case .moveRight, .moveLeft: Array(repeating: 0.16, count: 8)
        case .wave: [1.25, 0.18, 0.45, 1.32]
        case .jump: [1.5, 0.13, 0.15, 0.15, 1.27]
        case .disappointed: [0.7, 0.35, 0.2, 0.25, 0.45, 0.2, 0.35, 0.7]
        case .waiting: [0.65, 0.5, 0.18, 0.5, 0.5, 0.67]
        case .thinking: [0.65, 0.5, 0.25, 0.18, 0.7, 0.72]
        case .reviewing: [0.6, 0.5, 0.5, 0.18, 0.62, 0.6]
        case .lookAround: Array(repeating: 0.2, count: 16)
        }
    }
    var duration: Double { durations.reduce(0, +) }
    func asset(for kind: CompanionKind) -> String {
        let character = kind == .dusk ? "Dusk" : kind.rawValue.prefix(1).uppercased() + kind.rawValue.dropFirst()
        return "Companion" + character + "Motion" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    func frame(at elapsed: Double) -> Int {
        var time = max(0, elapsed).truncatingRemainder(dividingBy: duration)
        for (index, hold) in durations.enumerated() {
            if time < hold { return index }
            time -= hold
        }
        return durations.count - 1
    }

    // A reaction temporarily overlays the chosen mood; it never changes the mood.
    static func pose(for motion: Self?, mood: Mood, elapsed: Double,
                     petting: Bool = false, reducedMotion: Bool) -> DotlingPose {
        if reducedMotion { return mood == .happy ? .frame(.idle, 0) : .rest(mood) }
        if petting { return .frame(.idle, 3) }
        if let motion, elapsed < motion.duration {
            return .frame(motion, motion.frame(at: elapsed))
        }
        if mood == .happy {
            return .frame(.idle, Self.idle.frame(at: elapsed - (motion?.duration ?? 0)))
        }
        return .rest(mood)
    }
}

enum DotlingPose: Equatable {
    case rest(Mood)
    case frame(DotlingAnimation, Int)
}

struct DotlingAnimationView: View {
    var kind: CompanionKind
    var mood: Mood
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var motion: DotlingAnimation?
    @State private var idleImages: [UIImage] = []
    @State private var restImage: UIImage?
    @State private var actionImages: [UIImage] = []
    @State private var loadingAction: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var startedAt = ProcessInfo.processInfo.systemUptime
    @State private var visible = false
    @State private var petting = false
    @GestureState private var gestureActive = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60,
                                paused: !visible || reduceMotion || scenePhase != .active
                                    || petting || (mood != .happy && motion == nil))) { _ in
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let pose = DotlingAnimation.pose(for: motion, mood: mood, elapsed: elapsed,
                                               petting: petting, reducedMotion: reduceMotion)
            if let image = image(for: pose) ?? restImage ?? CompanionArt.displayImage(mood, kind: kind) {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .task(id: startedAt) {
            guard let motion else { return }
            let remaining = max(0, motion.duration - (ProcessInfo.processInfo.systemUptime - startedAt))
            do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled else { return }
            rest()
        }
        .contentShape(Ellipse())
        .onTapGesture(count: 2) { play(.jump) }
        .onTapGesture { play(.wave) }
        .simultaneousGesture(DragGesture(minimumDistance: 10)
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { _ in
                petting = true
            }
            .onEnded { value in
                petting = false
                if abs(value.translation.width) > 60 {
                    play(value.translation.width > 0 ? .moveRight : .moveLeft)
                } else { rest() }
            })
        .onChange(of: gestureActive) { _, active in
            if !active && petting { petting = false; rest() }
        }
        .contextMenu {
            ForEach(DotlingAnimation.allCases) { action in
                Button(action.title) { play(action) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title), feeling \(mood.title.lowercased())")
        .accessibilityHint("Tap to wave, double tap to hop, rub to pet, or hold for more movements")
        .accessibilityActions {
            ForEach(DotlingAnimation.allCases) { action in
                Button(action.title) { play(action) }
            }
        }
        .task(id: kind) {
            visible = true
            let currentKind = kind, currentMood = mood
            let artwork = await Task.detached(priority: .userInitiated) {
                (CompanionArt.motionFrames(.idle, kind: currentKind),
                 CompanionArt.displayImage(currentMood, kind: currentKind))
            }.value
            guard !Task.isCancelled else { return }
            idleImages = artwork.0
            restImage = artwork.1
            rest()
        }
        .onDisappear {
            visible = false; petting = false
            loadingAction?.cancel(); requestID = UUID()
            actionImages = []; idleImages = []; restImage = nil
        }
        .onChange(of: scenePhase) { _, phase in
            petting = false
            rest()
        }
        .onChange(of: reduceMotion) { _, _ in petting = false; rest() }
    }

    private func image(for pose: DotlingPose) -> UIImage? {
        switch pose {
        case .rest: return restImage
        case let .frame(action, index):
            let images = action == .idle ? idleImages : actionImages
            return images.indices.contains(index) ? images[index] : nil
        }
    }

    private func rest() {
        loadingAction?.cancel(); requestID = UUID()
        motion = nil; actionImages = []
        startedAt = ProcessInfo.processInfo.systemUptime
    }

    private func play(_ next: DotlingAnimation) {
        rest()
        let request = requestID
        if reduceMotion { return }
        if next == .idle {
            motion = .idle
            actionImages = []
            startedAt = ProcessInfo.processInfo.systemUptime
            return
        }
        let currentKind = kind
        loadingAction = Task {
            // Decode a complete strip once off the main thread before starting its clock.
            let frames = await Task.detached(priority: .userInitiated) {
                CompanionArt.motionFrames(next, kind: currentKind)
            }.value
            guard !Task.isCancelled, requestID == request,
                  frames.count == next.durations.count else { return }
            actionImages = frames
            motion = next
            startedAt = ProcessInfo.processInfo.systemUptime
        }
    }
}
