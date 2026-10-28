import SwiftUI
import UIKit

enum DotsStyle {
    static let paper = Color(red: 0.98, green: 0.96, blue: 0.93)
    static let ink = Color(red: 0.20, green: 0.18, blue: 0.26)
    static let muted = Color(red: 0.49, green: 0.46, blue: 0.52)
    static let plum = Color(red: 0.43, green: 0.34, blue: 0.57)
    static let lilac = Color(red: 0.90, green: 0.85, blue: 0.96)
    static func round(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func brand(_ size: CGFloat) -> Font { .custom("Nunito-ExtraBold", size: size) }
}

extension Mood {
    var color: Color {
        switch self {
        case .happy: Color(red: 0.97, green: 0.79, blue: 0.25)
        case .calm: Color(red: 0.40, green: 0.69, blue: 0.49)
        case .sleepy: Color(red: 0.46, green: 0.43, blue: 0.72)
        case .sad: Color(red: 0.39, green: 0.61, blue: 0.81)
        case .overwhelmed: Color(red: 0.89, green: 0.46, blue: 0.42)
        case .focused: Color(red: 0.91, green: 0.65, blue: 0.24)
        }
    }
}

enum CompanionArt {
    static var directory: URL?
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 24
        return cache
    }()
    // New action strips can have their own layout; existing mood atlases stay compatible.
    static func usesBlinkStrip(_ mood: Mood, kind: CompanionKind) -> Bool {
        kind == .dusk && mood == .happy
    }
    static func image(_ mood: Mood, kind: CompanionKind = .lavender) -> UIImage? {
        usesBlinkStrip(mood, kind: kind)
            ? frame(0, asset: "CompanionDuskBlink", columns: 6, rows: 1)
            : frame(mood.spriteIndex, asset: kind.asset)
    }
    static func touchImage(_ index: Int, kind: CompanionKind, mood: Mood = .happy) -> UIImage? {
        usesBlinkStrip(mood, kind: kind)
            ? frame(index, asset: "CompanionDuskBlink", columns: 6, rows: 1)
            : frame(index, asset: kind.touchAsset)
    }
    static func motionImage(_ motion: DotlingAnimation, frame index: Int, kind: CompanionKind = .dusk) -> UIImage? {
        frame(index, asset: motion.asset(for: kind), columns: motion.durations.count, rows: 1)
    }
    static func motionFrames(_ motion: DotlingAnimation, kind: CompanionKind) -> [UIImage] {
        let asset = motion.asset(for: kind)
        let url = directory?.appendingPathComponent(asset + ".png")
            ?? Bundle.main.url(forResource: asset, withExtension: "png")
            ?? Bundle.main.url(forResource: asset, withExtension: "png", subdirectory: "Resources")
        guard let url, let data = try? Data(contentsOf: url), let source = UIImage(data: data)?.cgImage,
              source.width % motion.durations.count == 0 else { return [] }
        // ImageIO crops can retain a lazy PNG provider. Decode the whole strip
        // once so individual frames never re-read or re-decompress the file.
        guard let atlasContext = CGContext(data: nil, width: source.width, height: source.height,
                                           bitsPerComponent: 8, bytesPerRow: source.width * 4,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        atlasContext.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let decoded = atlasContext.makeImage() else { return [] }
        let width = source.width / motion.durations.count, height = source.height
        return motion.durations.indices.compactMap { index in
            guard let cell = decoded.cropping(to: CGRect(x: index * width, y: 0, width: width, height: height)),
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(cell, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage().map { UIImage(cgImage: $0) }
        }
    }
    static func eggImage(_ stage: EggStage) -> UIImage? {
        frame(stage.frame, asset: stage.asset)
    }
    private static func frame(_ index: Int, asset: String, columns: Int = 3, rows: Int = 2) -> UIImage? {
        guard (0..<(columns * rows)).contains(index) else { return nil }
        let key = (directory?.path ?? "bundle") + asset + "/\(columns)x\(rows)/\(index)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let url = directory?.appendingPathComponent(asset + ".png")
            ?? Bundle.main.url(forResource: asset, withExtension: "png")
            ?? Bundle.main.url(forResource: asset, withExtension: "png", subdirectory: "Resources")
        guard let url, let data = try? Data(contentsOf: url), let source = UIImage(data: data)?.cgImage else { return nil }
        guard source.width % columns == 0, source.height % rows == 0 else { return nil }
        let width = source.width / columns, height = source.height / rows
        var crop = CGRect(x: (index % columns) * width, y: (index / columns) * height, width: width, height: height)
        var destination = CGRect(x: 0, y: 0, width: width, height: height)
        if let layout = (CompanionTouchLayout.frames[asset] ?? EggArtLayout.frames[asset])?[index] {
            crop = CGRect(x: layout[0], y: layout[1], width: layout[2], height: layout[3])
            let drawnWidth = layout[2] * layout[6], drawnHeight = layout[3] * layout[6]
            destination = CGRect(x: layout[4], y: CGFloat(height) - layout[5] - drawnHeight,
                                 width: drawnWidth, height: drawnHeight)
        }
        guard let cell = source.cropping(to: crop) else { return nil }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cell, in: destination)
        guard let decoded = context.makeImage() else { return nil }
        let result = UIImage(cgImage: decoded)
        cache.setObject(result, forKey: key as NSString, cost: width * height * 4)
        return result
    }
}

struct CompanionView: View {
    var mood: Mood
    var kind: CompanionKind = .lavender
    var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var touching = false
    @State private var rubDistance: CGFloat = 0
    @State private var previousPoint: CGPoint?
    @State private var lastFeedback = Date.distantPast
    @State private var playback = SpritePlayback(count: 7)
    @State private var playImages: [UIImage] = []
    @State private var loadedArtwork = ""
    @State private var petting = false
    @GestureState private var gestureActive = false
    private var artworkID: String { kind.rawValue + "/" + mood.rawValue }
    var body: some View {
        if animate && mood == .happy {
            DotlingAnimationView(kind: kind).id(kind)
        } else if animate {
            character
                .task(id: artworkID) {
                    let currentID = artworkID
                    let currentMood = mood, currentKind = kind
                    let images = await Task.detached(priority: .userInitiated) {
                        [CompanionArt.image(currentMood, kind: currentKind)] + (0..<6).map { CompanionArt.touchImage($0, kind: currentKind, mood: currentMood) }
                    }.value
                    guard !Task.isCancelled, images.allSatisfy({ $0 != nil }) else { return }
                    playImages = images.compactMap { $0 }
                    loadedArtwork = currentID
                }
                .contentShape(Ellipse())
                .gesture(playGesture)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Tap to boop, or rub to pet your companion")
                .accessibilityAction(named: "Boop") { react(rubbed: false) }
                .accessibilityAction(named: "Pet") { react(rubbed: true) }
                .onDisappear { stopPlaying() }
                .onChange(of: kind) { _, _ in stopPlaying() }
                .onChange(of: mood) { _, _ in stopPlaying() }
                .onChange(of: reduceMotion) { _, _ in stopPlaying() }
                .onChange(of: scenePhase) { _, phase in if phase != .active { stopPlaying() } }
                .onChange(of: gestureActive) { _, active in
                    // SwiftUI also resets GestureState when a parent scroll view cancels a drag.
                    if !active && touching { endTouch() }
                }
        } else { character }
    }

    private var character: some View {
        Group {
            if animate && loadedArtwork == artworkID && playImages.count == 7 {
                PlayingSprite(images: playImages, playback: playback)
            } else if let image = CompanionArt.image(mood, kind: kind) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "cloud.fill").resizable().scaledToFit().foregroundStyle(DotsStyle.lilac)
            }
        }
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Squishy companion, feeling \(mood.title.lowercased())")
    }

    private var playGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { value in
                if !touching {
                    petting = false
                    TouchFeedback.prepare()
                    playFrames(rubbed: false)
                }
                touching = true
                if let previousPoint {
                    let distance = hypot(value.location.x - previousPoint.x, value.location.y - previousPoint.y)
                    rubDistance += distance
                    if distance > 1, rubDistance > 15, Date().timeIntervalSince(lastFeedback) > 0.10 {
                        TouchFeedback.pet()
                        lastFeedback = Date()
                    }
                }
                previousPoint = value.location
                if rubDistance > 30, !petting { playFrames(rubbed: true) }
            }
            .onEnded { _ in endTouch() }
    }

    private func endTouch() {
        guard touching else { return }
        let rubbed = rubDistance > 30
        touching = false; previousPoint = nil; rubDistance = 0
        if rubbed {
            playback.play([0], interval: 0.24, at: ProcessInfo.processInfo.systemUptime)
            petting = false
        } else { TouchFeedback.tap() }
    }
    private func stopPlaying() {
        touching = false; petting = false
        playback = SpritePlayback(count: 7)
        previousPoint = nil; rubDistance = 0
    }
    private func react(rubbed: Bool) {
        if rubbed { TouchFeedback.pet() } else { TouchFeedback.tap() }
        playFrames(rubbed: rubbed)
    }
    private func playFrames(rubbed: Bool) {
        guard loadedArtwork == artworkID, playImages.count == 7 else { return }
        petting = rubbed
        if CompanionArt.usesBlinkStrip(mood, kind: kind) {
            let sequence = CompanionMotion.blink(rubbed: rubbed, held: touching, reducedMotion: reduceMotion)
            playback.play(sequence, interval: reduceMotion ? 0.3 : 0.14, at: ProcessInfo.processInfo.systemUptime)
            return
        }
        let frames: [Int] = reduceMotion ? [rubbed ? 5 : 3, 0] : (rubbed ? CompanionMotion.rub + (touching ? [] : [1, 0]) : CompanionMotion.tap)
        playback.play(frames, interval: reduceMotion ? 0.3 : rubbed ? CompanionMotion.rubInterval : CompanionMotion.tapInterval,
                      repeats: rubbed && touching && !reduceMotion, at: ProcessInfo.processInfo.systemUptime)
    }

}

struct DotsProgress: View {
    var value: Double
    var total: Double = 1
    var label = "Progress"
    private var fraction: Double { total > 0 ? min(1, max(0, value / total)) : 0 }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(DotsStyle.plum.opacity(0.12))
                Capsule().fill(DotsStyle.plum).frame(width: geometry.size.width * fraction)
            }
        }.frame(height: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label).accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

struct MoodBadge: View {
    var mood: Mood
    var body: some View {
        Label(mood.title, systemImage: mood.symbol)
            .font(DotsStyle.round(13, weight: .semibold))
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(mood.color.opacity(0.25), in: Capsule())
            .foregroundStyle(DotsStyle.ink)
    }
}

struct FriendWidgetView: View {
    var friend: Companion?
    var circular = false
    var inline = false
    var body: some View {
        if inline {
            Label(friend.map { "\($0.ownerName) · \($0.mood.title)" } ?? "Open Dotlings to add a friend", systemImage: friend?.mood.symbol ?? "heart")
                .font(.system(size: 12, weight: .medium, design: .rounded)).lineLimit(1)
        } else if circular {
            VStack(spacing: 1) {
                if let friend {
                    CompanionView(mood: friend.mood, kind: friend.kind).frame(width: 44, height: 44)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: friend.mood.symbol).font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(friend.mood.color)
                        }
                } else { Image(systemName: "person.2").font(.system(size: 20, weight: .medium)) }
                Text(friend?.ownerName ?? "Dotlings").font(.system(size: 10, weight: .semibold)).lineLimit(1)
            }.accessibilityLabel(friend.map { "\($0.ownerName) is feeling \($0.mood.title)" } ?? "No friend selected")
        } else if let friend {
            HStack(spacing: 8) {
                CompanionView(mood: friend.mood, kind: friend.kind).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.ownerName).font(.system(.headline, design: .rounded)).lineLimit(1)
                    Text(friend.mood.title).font(.caption).lineLimit(1).foregroundStyle(friend.mood.color)
                    Text(friend.updatedAt, style: .relative).font(.system(size: 9)).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Label("A little closer", systemImage: "heart.fill").font(.headline)
                Text("Open Dotlings to add a friend").font(.caption)
            }
        }
    }
}

// Retain and prepare generators so feedback starts promptly on real iPhones.
@MainActor enum TouchFeedback {
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let firm = UIImpactFeedbackGenerator(style: .rigid)
    private static let success = UINotificationFeedbackGenerator()
    static func prepare() { soft.prepare(); firm.prepare(); success.prepare() }
    static func pet() { soft.impactOccurred(intensity: 0.65); soft.prepare() }
    static func tap() { firm.impactOccurred(intensity: 0.55); firm.prepare() }
    static func shell(warmth: Double) { firm.impactOccurred(intensity: 0.4 + warmth * 0.5); firm.prepare(); success.prepare() }
    static func hatch() { success.notificationOccurred(.success) }
    static func hatchBeat(_ intensity: CGFloat) { soft.impactOccurred(intensity: intensity); soft.prepare() }
}
