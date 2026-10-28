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

    static func pose(for motion: Self, elapsed: Double, reducedMotion: Bool) -> (Self, Int) {
        if reducedMotion { return (.idle, 0) }
        if motion != .idle && elapsed >= motion.duration {
            return (.idle, Self.idle.frame(at: elapsed - motion.duration))
        }
        return (motion, motion.frame(at: elapsed))
    }
}

struct DotlingAnimationView: View {
    var kind: CompanionKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var motion = DotlingAnimation.idle
    @State private var idleImages: [UIImage] = []
    @State private var actionImages: [UIImage] = []
    @State private var loadingAction: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var startedAt = ProcessInfo.processInfo.systemUptime
    @State private var visible = false
    @State private var petting = false
    @State private var lastFeedback = 0.0
    @GestureState private var gestureActive = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60,
                                paused: !visible || reduceMotion || scenePhase != .active)) { _ in
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let pose = petting && !reduceMotion ? (DotlingAnimation.idle, 3)
                : DotlingAnimation.pose(for: motion, elapsed: elapsed, reducedMotion: reduceMotion)
            let images = pose.0 == .idle ? idleImages : actionImages
            if images.indices.contains(pose.1) {
                Image(uiImage: images[pose.1]).resizable().scaledToFit()
            } else if let image = idleImages.first ?? CompanionArt.image(.happy, kind: kind) {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .contentShape(Ellipse())
        .onTapGesture(count: 2) { play(.jump); TouchFeedback.tap() }
        .onTapGesture { play(.wave); TouchFeedback.tap() }
        .simultaneousGesture(DragGesture(minimumDistance: 10)
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { _ in
                petting = true
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastFeedback > 0.12 {
                    TouchFeedback.pet(); lastFeedback = now
                }
            }
            .onEnded { value in
                petting = false
                if abs(value.translation.width) > 60 {
                    play(value.translation.width > 0 ? .moveRight : .moveLeft)
                } else { play(.idle) }
            })
        .onChange(of: gestureActive) { _, active in
            if !active && petting { petting = false; play(.idle) }
        }
        .contextMenu {
            ForEach(DotlingAnimation.allCases) { action in
                Button(action.title) { play(action) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title), feeling happy")
        .accessibilityHint("Tap to wave, double tap to hop, rub to pet, or hold for more movements")
        .accessibilityActions {
            ForEach(DotlingAnimation.allCases) { action in
                Button(action.title) { play(action) }
            }
        }
        .task(id: kind) {
            visible = true
            let currentKind = kind
            let frames = await Task.detached(priority: .userInitiated) {
                CompanionArt.motionFrames(.idle, kind: currentKind)
            }.value
            guard !Task.isCancelled else { return }
            idleImages = frames
            play(.idle)
        }
        .onDisappear {
            visible = false; petting = false
            loadingAction?.cancel(); requestID = UUID()
            actionImages = []; idleImages = []
        }
        .onChange(of: scenePhase) { _, phase in
            petting = false
            if phase == .active { play(.idle) }
        }
        .onChange(of: reduceMotion) { _, _ in petting = false; play(.idle) }
    }

    private func play(_ next: DotlingAnimation) {
        loadingAction?.cancel()
        let request = UUID()
        requestID = request
        if next == .idle || reduceMotion {
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
