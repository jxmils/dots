import SwiftUI

enum EggStage: Int, CaseIterable {
    case sleeping, warming, awake, stirringLeft, stirringRight, firstCrack
    case secondCrack, gatheringLight, opening, lifting, parting, nest

    var asset: String { rawValue < 6 ? "EggWakeAtlas" : "EggOpenAtlas" }
    var frame: Int { rawValue % 6 }
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
    var body: some View {
        Group {
            if let image = CompanionArt.eggImage(stage) {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }.transaction { $0.animation = nil }.accessibilityHidden(true)
    }
}

struct HatchPortrait: View {
    var kind: CompanionKind
    var body: some View {
        ZStack {
            CompanionView(mood: .happy, kind: kind, animate: true)
                .frame(width: 230, height: 230).offset(y: -18)
            EggArtwork(stage: .nest).allowsHitTesting(false)
        }.frame(width: 320, height: 320)
    }
}
