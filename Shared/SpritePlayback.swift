import SwiftUI
import UIKit

enum CompanionMotion {
    // Six drawn eyelid positions, played forward and back without deforming the pet.
    static let tap = [1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1, 0]
    static let rub = [1, 2, 3, 4, 5, 6, 5, 4, 3, 2]
    static let tapInterval = 0.055
    static let rubInterval = 0.09

    // The new strip is a complete blink, rather than six progressively closed lids.
    // Hold the closed drawing while petting; release eases back to the selected mood.
    static func blink(rubbed: Bool, held: Bool, reducedMotion: Bool) -> [Int] {
        if reducedMotion { return [0] }
        if rubbed && held { return [2, 3, 4] }
        return rubbed ? [2, 3, 4, 4, 5, 6, 0] : [2, 3, 4, 5, 6, 0]
    }
}

// Interpolate artwork weights, never the character's geometry. Sampling elapsed
// time keeps the animation continuous even if a display frame arrives late.
struct SpritePlayback: Equatable {
    private(set) var origin: [Double]
    private(set) var frames: [Int] = []
    private(set) var startedAt = 0.0
    private(set) var interval = 0.2
    private(set) var repeats = false

    init(count: Int, restingFrame: Int = 0) {
        origin = Array(repeating: 0, count: count)
        origin[restingFrame] = 1
    }

    func weights(at time: TimeInterval) -> [Double] {
        guard !frames.isEmpty else { return origin }
        let position = max(0, time - startedAt) / interval
        if !repeats && position >= Double(frames.count) { return pose(frames.last!) }
        let step = Int(position)
        let fraction = position - Double(step)
        let eased = fraction * fraction * (3 - 2 * fraction)
        let from = step == 0 ? origin : pose(frames[(step - 1) % frames.count])
        let to = pose(frames[step % frames.count])
        return zip(from, to).map { $0 + ($1 - $0) * eased }
    }

    func isMoving(at time: TimeInterval) -> Bool {
        guard !frames.isEmpty else { return false }
        return (repeats && frames.count > 1) || time < startedAt + Double(frames.count) * interval
    }

    mutating func play(_ next: [Int], interval: Double, repeats: Bool = false, at time: TimeInterval) {
        precondition(!next.isEmpty && next.allSatisfy { origin.indices.contains($0) } && interval > 0)
        origin = weights(at: time)
        frames = next
        startedAt = time
        self.interval = interval
        self.repeats = repeats
    }

    private func pose(_ index: Int) -> [Double] {
        var result = Array(repeating: 0.0, count: origin.count)
        result[index] = 1
        return result
    }
}

struct SpriteCanvas: View {
    var images: [UIImage]
    var weights: [Double]

    var body: some View {
        Canvas { context, size in
            let edge = min(size.width, size.height)
            let rect = CGRect(x: (size.width - edge) / 2, y: (size.height - edge) / 2, width: edge, height: edge)
            // Add premultiplied colors in an isolated transparent layer. Ordinary
            // stacked opacity would make the pet translucent midway through a fade.
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                for (image, weight) in zip(images, weights) where weight > 0 {
                    layer.opacity = weight
                    layer.draw(Image(uiImage: image), in: rect)
                }
            }
        }.accessibilityHidden(true)
    }
}

struct PlayingSprite: View {
    var images: [UIImage]
    var playback: SpritePlayback
    @State private var ticking = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !ticking)) { _ in
            SpriteCanvas(images: images, weights: playback.weights(at: ProcessInfo.processInfo.systemUptime))
        }
        .task(id: playback) {
            ticking = playback.isMoving(at: ProcessInfo.processInfo.systemUptime)
            guard ticking else { return }
            if !playback.repeats || playback.frames.count == 1 {
                let remaining = max(0, playback.startedAt + Double(playback.frames.count) * playback.interval - ProcessInfo.processInfo.systemUptime)
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
                ticking = false
            }
        }
        .onDisappear { ticking = false }
    }
}
