import SwiftUI
import UIKit

enum DotlingAnimation: String, CaseIterable, Identifiable {
    case idle, moveRight, moveLeft, wave, jump, disappointed, waiting, thinking, reviewing, lookAround
    var id: String { rawValue }
    static let automaticInterval: UInt64 = 10_000_000_000
    static func automaticChoices(after previous: Self?) -> [Self] {
        allCases.filter { $0 != previous }
    }
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
    @State private var signature = false
    @State private var signatureImage: UIImage?
    @State private var motion: DotlingAnimation?
    @State private var idleImages: [UIImage] = []
    @State private var restImage: UIImage?
    @State private var actionImages: [UIImage] = []
    @State private var loadingAction: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var startedAt = ProcessInfo.processInfo.systemUptime
    @State private var visible = false
    @State private var petting = false
    @State private var lastAutomaticEmote: DotlingAnimation?
    @GestureState private var gestureActive = false

    private var automaticEmotesEnabled: Bool {
        visible && scenePhase == .active && !reduceMotion
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60,
                                paused: !visible || reduceMotion || scenePhase != .active
                                    || (mood != .happy && motion == nil && !signature))) { _ in
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let pose = DotlingAnimation.pose(for: motion, mood: mood, elapsed: elapsed,
                                               petting: false, reducedMotion: reduceMotion)
            if signature, let image = signatureImage {
                DotlingSignatureImage(image: image, reaction: .reaction(for: kind), elapsed: elapsed, reducedMotion: reduceMotion)
            } else if let image = image(for: pose) ?? restImage ?? CompanionArt.displayImage(mood, kind: kind) {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .task(id: startedAt) {
            guard signature || motion != nil else { return }
            let duration = signature ? DotlingSignature.reaction(for: kind).duration : motion!.duration
            let remaining = max(0, duration - (ProcessInfo.processInfo.systemUptime - startedAt))
            do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled else { return }
            rest()
        }
        .task(id: automaticEmotesEnabled) {
            guard automaticEmotesEnabled else { return }
            // A separate clock keeps the ten-second cadence independent of an
            // emote finishing. Cancellation prevents offscreen/background playback.
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: DotlingAnimation.automaticInterval) }
                catch { return }
                guard !Task.isCancelled else { return }
                // Let touch reactions and frame decoding finish without interruption.
                guard !petting, !gestureActive, !signature, motion == nil,
                      loadingAction == nil, !idleImages.isEmpty,
                      let next = DotlingAnimation.automaticChoices(after: lastAutomaticEmote).randomElement()
                else { continue }
                lastAutomaticEmote = next
                play(next)
            }
        }
        .contentShape(Ellipse())
        .onTapGesture(count: 2) { play(.jump) }
        .onTapGesture { playSignature() }
        .simultaneousGesture(DragGesture(minimumDistance: 10)
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { _ in
                if !signature { playSignature() }
                petting = true
            }
            .onEnded { value in
                petting = false
                if abs(value.translation.width) > 60 {
                    play(value.translation.width > 0 ? .moveRight : .moveLeft)
                }
            })
        .onChange(of: gestureActive) { _, active in
            if !active && petting { petting = false }
        }
        .contextMenu {
            Button(DotlingSignature.reaction(for: kind).title) { playSignature() }
            ForEach(DotlingAnimation.allCases) { action in
                Button(action.title) { play(action) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title), feeling \(mood.title.lowercased())")
        .accessibilityHint("Plays a random emote every ten seconds. Tap for a little reaction, double tap to hop, or rub to pet.")
        .accessibilityActions {
            Button(DotlingSignature.reaction(for: kind).title) { playSignature() }
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
        loadingAction?.cancel(); loadingAction = nil; requestID = UUID()
        signature = false; signatureImage = nil
        motion = nil; actionImages = []
        startedAt = ProcessInfo.processInfo.systemUptime
    }

    private func playSignature() {
        guard !reduceMotion, !signature else { return }
        // Freeze the current resting mood during the reaction; no smiling
        // replacement face, pose swapping, or size changes on touch.
        let image = restImage ?? CompanionArt.displayImage(mood, kind: kind)
        rest()
        guard let image else { return }
        signatureImage = image
        signature = true
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
            guard !Task.isCancelled, requestID == request else { return }
            loadingAction = nil
            guard frames.count == next.durations.count else { return }
            actionImages = frames
            motion = next
            startedAt = ProcessInfo.processInfo.systemUptime
        }
    }
}

// A single, mood-preserving reaction per kind. Values are fractions of the
// fixed canvas, never scale factors. The approved artwork stays the source.
struct DotlingSignature {
    enum Style { case drift, rock, nod, leaves }
    var title: String
    var style: Style
    var duration: Double
    var amount: Double
    var foliageHeight: Double = 0.32

    static func reaction(for kind: CompanionKind) -> Self {
        switch kind {
        case .lavender: .init(title: "Little hello", style: .rock, duration: 1.8, amount: 0.9)
        case .blue: .init(title: "Shy sway", style: .rock, duration: 1.9, amount: 1.0)
        case .pillow: .init(title: "Cloud drift", style: .drift, duration: 2.4, amount: 0.009)
        case .pebble: .init(title: "Pebble rock", style: .rock, duration: 1.8, amount: 0.7)
        case .sprout: .init(title: "Leaf wiggle", style: .leaves, duration: 2.0, amount: 0.012)
        case .twinkle: .init(title: "Star tilt", style: .rock, duration: 1.7, amount: 1.2)
        case .pudding: .init(title: "Pudding wobble", style: .rock, duration: 2.1, amount: 1.1)
        case .bean: .init(title: "Bean nod", style: .nod, duration: 1.7, amount: 0.005)
        case .ember: .init(title: "Ember float", style: .drift, duration: 1.9, amount: 0.006)
        case .moss: .init(title: "Moss sway", style: .rock, duration: 2.3, amount: 0.6)
        case .luna: .init(title: "Moon drift", style: .drift, duration: 2.6, amount: 0.007)
        case .bubble: .init(title: "Bubble float", style: .drift, duration: 2.1, amount: 0.01)
        case .snow: .init(title: "Snow settle", style: .nod, duration: 2.4, amount: 0.004)
        case .sunny: .init(title: "Sunny nod", style: .nod, duration: 1.8, amount: 0.006)
        case .dusk: .init(title: "Quiet hello", style: .rock, duration: 2.2, amount: 0.75)
        case .petal: .init(title: "Petal sway", style: .rock, duration: 2.0, amount: 0.85)
        case .nimbus: .init(title: "Nimbus drift", style: .drift, duration: 2.5, amount: 0.008)
        case .toast: .init(title: "Toast tip", style: .rock, duration: 1.6, amount: 0.8)
        case .puff: .init(title: "Puff settle", style: .nod, duration: 2.2, amount: 0.005)
        case .ripple: .init(title: "Ripple sway", style: .drift, duration: 2.2, amount: 0.008)
        case .onion: .init(title: "Onion sway", style: .rock, duration: 2.1, amount: 0.8)
        case .cumulus: .init(title: "Floss float", style: .drift, duration: 2.3, amount: 0.01)
        case .bonsai: .init(title: "Canopy rustle", style: .leaves, duration: 2.4, amount: 0.008, foliageHeight: 0.48)
        case .droplet: .init(title: "Dew bob", style: .nod, duration: 2.0, amount: 0.007)
        case .drizzle: .init(title: "Raincloud drift", style: .drift, duration: 2.7, amount: 0.006)
        case .storm: .init(title: "Storm sway", style: .rock, duration: 1.9, amount: 0.65)
        case .bowling: .init(title: "Tiny roll", style: .rock, duration: 2.0, amount: 1.3)
        case .coffee: .init(title: "Coffee nod", style: .nod, duration: 1.6, amount: 0.004)
        case .coconut: .init(title: "Coconut rock", style: .rock, duration: 2.3, amount: 0.9)
        }
    }

    func phase(at elapsed: Double, reducedMotion: Bool = false) -> Double {
        guard !reducedMotion, elapsed > 0, elapsed < duration else { return 0 }
        let t = elapsed / duration
        // Zero position AND velocity at both ends, with a soft return to rest.
        return sin(t * .pi * 2) * pow(sin(t * .pi), 2)
    }
}

struct DotlingSignatureImage: View {
    let image: UIImage
    let reaction: DotlingSignature
    let elapsed: Double
    var reducedMotion = false

    var body: some View {
        Canvas { context, size in
            let fit = min(size.width / image.size.width, size.height / image.size.height)
            let width = image.size.width * fit, height = image.size.height * fit
            let rect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                              width: width, height: height)
            let resolved = context.resolve(Image(uiImage: image))
            let phase = reaction.phase(at: elapsed, reducedMotion: reducedMotion)
            switch reaction.style {
            case .drift:
                context.translateBy(x: width * reaction.amount * phase, y: -height * reaction.amount * phase * 0.35)
                context.draw(resolved, in: rect)
            case .nod:
                context.translateBy(x: 0, y: height * reaction.amount * phase)
                context.draw(resolved, in: rect)
            case .rock:
                context.translateBy(x: rect.midX, y: rect.maxY)
                context.rotate(by: .degrees(reaction.amount * phase))
                context.translateBy(x: -rect.midX, y: -rect.maxY)
                context.draw(resolved, in: rect)
            case .leaves:
                if abs(phase) < 0.00001 {
                    context.draw(resolved, in: rect)
                } else {
                    // Shift only the crown, tapering to zero above the face.
                    // Render at screen-pixel band height to retain the original
                    // texture and alpha without redrawing or stretching the pet.
                    let crown = height * reaction.foliageHeight
                    let bands = max(1, Int(ceil(crown * image.scale * 3)))
                    for band in 0..<bands {
                        let y = crown * Double(band) / Double(bands)
                        let nextY = crown * Double(band + 1) / Double(bands)
                        var strip = context
                        strip.clip(to: Path(CGRect(x: 0, y: rect.minY + y, width: size.width, height: nextY - y)), style: FillStyle(antialiased: false))
                        let weight = pow(min(1, (crown - (y + nextY) / 2) / (crown - height * 0.12)), 2)
                        strip.translateBy(x: width * reaction.amount * phase * weight, y: 0)
                        strip.draw(resolved, in: rect)
                    }
                    context.clip(to: Path(CGRect(x: 0, y: rect.minY + crown, width: size.width, height: size.height)), style: FillStyle(antialiased: false))
                    context.draw(resolved, in: rect)
                }
            }
        }
    }
}
