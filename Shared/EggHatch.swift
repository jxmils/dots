import SwiftUI

enum EggStage: Int, CaseIterable {
    case sleeping, stirringLeft, warming, stirringRight, awake, awakeSettled
    case crackStart, firstCrack, crackGrowing, secondCrack, gatheringLight, capLoosened
    case hatchStart, tuft, opening, lifting, parting, peeking
    case revealStart, rising, smiling, armsOut, blink, nest

    var needsCompanion: Bool { rawValue >= EggStage.hatchStart.rawValue }
    var frame: Int { needsCompanion ? rawValue - EggStage.hatchStart.rawValue : rawValue % 6 }
    var columns: Int { needsCompanion ? 12 : 6 }
    func asset(for kind: CompanionKind?) -> String? {
        if rawValue < 6 { return "EggWakingStrip" }
        if rawValue < 12 { return "EggCrackingStrip" }
        guard let kind else { return nil }
        return "EggHatch\(kind.rawValue.prefix(1).uppercased())\(kind.rawValue.dropFirst())Strip"
    }

    // Authored sprite timing from the approved preview; no geometric deformation.
    static func ceremony(reduceMotion: Bool) -> [(stage: EggStage, milliseconds: Int)] {
        if reduceMotion { return [(.capLoosened, 650), (.nest, 1600)] }
        return [(.gatheringLight, 180), (.capLoosened, 250),
                (.tuft, 160), (.opening, 160), (.lifting, 160), (.parting, 180), (.peeking, 380),
                (.rising, 160), (.smiling, 160), (.armsOut, 250), (.blink, 170), (.nest, 1600)]
    }
}

struct HatchRitual {
    private(set) var warmth = 0.0
    private(set) var cracks = 0
    private(set) var isOpening = false

    var ready: Bool { warmth >= 1 }
    var stage: EggStage {
        if cracks >= 2 { return .secondCrack }
        if cracks == 1 { return .firstCrack }
        return warmth < 0.3 ? .sleeping : warmth < 0.7 ? .warming : .awake
    }

    mutating func warm(_ amount: Double) {
        guard !isOpening, amount.isFinite, amount > 0 else { return }
        warmth = min(1, warmth + amount)
    }

    // Returns true exactly once when the third crack starts the reveal.
    mutating func tap() -> Bool {
        guard !isOpening else { return false }
        guard ready else { warm(0.25); return false }
        cracks += 1
        isOpening = cracks == 3
        return isOpening
    }

    mutating func retryOpening() {
        guard isOpening else { return }
        cracks = 2
        isOpening = false
    }
}

struct EggArtwork: View {
    var stage: EggStage
    var kind: CompanionKind? = nil
    var frames: [UIImage] = []
    @State private var images: [UIImage] = []
    @State private var loadedKind: CompanionKind?

    private var image: UIImage? {
        let available = frames.isEmpty && loadedKind == kind ? images : frames
        if available.indices.contains(stage.rawValue) { return available[stage.rawValue] }
        return CompanionArt.eggImage(stage, kind: kind)
            ?? CompanionArt.eggImage(.capLoosened)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .task(id: kind) {
            guard frames.isEmpty else { return }
            let requestedKind = kind
            let loaded = await Task.detached(priority: .userInitiated) {
                CompanionArt.eggFrames(kind: requestedKind)
            }.value
            guard !Task.isCancelled else { return }
            loadedKind = requestedKind
            images = loaded
        }
        .transaction { $0.animation = nil }.accessibilityHidden(true)
    }
}

struct HatchPortrait: View {
    var kind: CompanionKind
    var frames: [UIImage] = []
    var body: some View {
        EggArtwork(stage: .nest, kind: kind, frames: frames)
            .frame(width: 320, height: 320).allowsHitTesting(false)
    }
}
