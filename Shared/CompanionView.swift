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
    static func image(_ mood: Mood, kind: CompanionKind = .lavender) -> UIImage? {
        let key = kind.rawValue + mood.rawValue
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let url = directory?.appendingPathComponent(kind.asset + ".png")
            ?? Bundle.main.url(forResource: kind.asset, withExtension: "png")
            ?? Bundle.main.url(forResource: kind.asset, withExtension: "png", subdirectory: "Resources")
        guard let url, let source = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        let width = source.width / 3, height = source.height / 2
        let i = mood.spriteIndex
        guard let cell = source.cropping(to: CGRect(x: (i % 3) * width, y: (i / 3) * height, width: width, height: height)) else { return nil }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cell, in: CGRect(x: 0, y: 0, width: width, height: height))
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
    @State private var hop: CGFloat = 0
    @State private var playfulTilt = 0.0
    @State private var tapCount = 0
    @State private var showHearts = false
    @State private var floating = false
    @State private var squished = false
    @State private var touching = false
    @State private var drag = CGSize.zero
    @State private var rubDistance: CGFloat = 0
    @State private var previousPoint: CGPoint?
    @State private var lastFeedback = Date.distantPast
    @State private var reaction: Mood?
    @State private var reactionTask: Task<Void, Never>?
    var body: some View {
        if animate {
            character
                .contentShape(Ellipse())
                .gesture(playGesture)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Tap to boop, or rub to pet your companion")
                .accessibilityAction(named: "Boop") { react(rubbed: false) }
                .accessibilityAction(named: "Pet") { react(rubbed: true) }
                .onDisappear { reactionTask?.cancel(); reaction = nil; squished = false; touching = false; hop = 0; playfulTilt = 0; showHearts = false }
        } else { character }
    }

    private var character: some View {
        Group {
            if let image = CompanionArt.image(reaction ?? mood, kind: kind) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "cloud.fill").resizable().scaledToFit().foregroundStyle(DotsStyle.lilac)
            }
        }
        .scaleEffect(x: reduceMotion ? 1 : squished || touching ? 1.10 : 1,
                     y: reduceMotion ? 1 : squished || touching ? 0.90 : 1, anchor: .bottom)
        .rotationEffect(.degrees(reduceMotion ? 0 : playfulTilt + Double(max(-8, min(8, drag.width / 14)))))
        .offset(x: reduceMotion ? 0 : max(-8, min(8, drag.width / 12)), y: reduceMotion ? 0 : hop + (floating ? -6 : 0))
        .overlay(alignment: .top) {
            if showHearts {
                HStack(spacing: 22) {
                    Image(systemName: "heart.fill").rotationEffect(.degrees(-18))
                    Image(systemName: "sparkle").offset(y: -12)
                    Image(systemName: "heart.fill").rotationEffect(.degrees(18))
                }.font(.system(size: 16)).foregroundStyle(DotsStyle.plum.opacity(0.7))
                    .transition(.opacity).allowsHitTesting(false)
            }
        }
        .onAppear {
            if animate && !reduceMotion {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { floating = true }
            }
        }
        .accessibilityLabel("Squishy companion, feeling \(mood.title.lowercased())")
    }

    private var playGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !touching { reactionTask?.cancel(); hop = 0; playfulTilt = 0; squished = false; showHearts = false; TouchFeedback.prepare() }
                touching = true
                drag = value.translation
                if let previousPoint {
                    let distance = hypot(value.location.x - previousPoint.x, value.location.y - previousPoint.y)
                    rubDistance += distance
                    if distance > 1, rubDistance > 15, Date().timeIntervalSince(lastFeedback) > 0.10 {
                        TouchFeedback.pet()
                        lastFeedback = Date()
                    }
                }
                previousPoint = value.location
                if rubDistance > 30 {
                    reaction = .calm
                }
            }
            .onEnded { _ in
                let rubbed = rubDistance > 30
                previousPoint = nil; rubDistance = 0
                withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.4)) { touching = false; drag = .zero }
                react(rubbed: rubbed)
            }
    }

    private func react(rubbed: Bool) {
        reactionTask?.cancel()
        reaction = rubbed ? .calm : .happy
        tapCount += 1
        if rubbed { TouchFeedback.pet() } else { TouchFeedback.tap() }
        withAnimation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.55)) {
            squished = true
            showHearts = rubbed
        }
        reactionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.55)) {
                squished = false
                hop = rubbed ? -4 : (tapCount.isMultiple(of: 3) ? -32 : -18)
                playfulTilt = rubbed ? 0 : (tapCount.isMultiple(of: 2) ? -12 : 12)
                showHearts = true
            }
            try? await Task.sleep(for: .milliseconds(230))
            guard !Task.isCancelled else { return }
            if !rubbed { TouchFeedback.land() }
            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.45)) {
                hop = 0; playfulTilt = 0
            }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { showHearts = false }
            reaction = nil
        }
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
    static func land() { soft.impactOccurred(intensity: 0.45); soft.prepare() }
    static func shell(warmth: Double) { firm.impactOccurred(intensity: 0.4 + warmth * 0.5); firm.prepare(); success.prepare() }
    static func hatch() { success.notificationOccurred(.success) }
}
