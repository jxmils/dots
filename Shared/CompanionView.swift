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
}

extension Mood {
    var color: Color {
        switch self {
        case .happy: Color(red: 0.96, green: 0.78, blue: 0.42)
        case .calm: Color(red: 0.63, green: 0.77, blue: 0.66)
        case .sleepy: Color(red: 0.73, green: 0.68, blue: 0.85)
        case .sad: Color(red: 0.63, green: 0.74, blue: 0.84)
        case .overwhelmed: Color(red: 0.87, green: 0.66, blue: 0.62)
        case .focused: Color(red: 0.86, green: 0.71, blue: 0.54)
        }
    }
}

enum CompanionArt {
    static var directory: URL?
    private static var cache: [String: UIImage] = [:]
    static func image(_ mood: Mood, kind: CompanionKind = .lavender) -> UIImage? {
        let key = kind.rawValue + mood.rawValue
        if let cached = cache[key] { return cached }
        let url = directory?.appendingPathComponent(kind.asset + ".png")
            ?? Bundle.main.url(forResource: kind.asset, withExtension: "png")
            ?? Bundle.main.url(forResource: kind.asset, withExtension: "png", subdirectory: "Resources")
        guard let url, let source = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        let width = source.width / 3, height = source.height / 2
        let i = mood.spriteIndex
        guard let cell = source.cropping(to: CGRect(x: (i % 3) * width, y: (i / 3) * height, width: width, height: height)) else { return nil }
        let result = UIImage(cgImage: cell)
        cache[key] = result
        return result
    }
}

struct CompanionView: View {
    var mood: Mood
    var kind: CompanionKind = .lavender
    var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false
    @State private var squished = false
    var body: some View {
        Group {
            if let image = CompanionArt.image(mood, kind: kind) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "cloud.fill").resizable().scaledToFit().foregroundStyle(DotsStyle.lilac)
            }
        }
        .scaleEffect(x: squished ? 1.10 : 1, y: squished ? 0.88 : 1, anchor: .bottom)
        .offset(y: floating && !reduceMotion ? -6 : 0)
        .onAppear {
            if animate && !reduceMotion {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { floating = true }
            }
        }
        .onTapGesture {
            guard animate else { return }
            if !reduceMotion { withAnimation(.spring(response: 0.25, dampingFraction: 0.35)) { squished = true } }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.4)) { squished = false }
            }
        }
        .accessibilityLabel("Squishy companion, feeling \(mood.title.lowercased())")
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
    var body: some View {
        if circular {
            VStack(spacing: 1) {
                Image(systemName: friend?.mood.symbol ?? "person.2")
                    .font(.system(size: 20, weight: .medium))
                Text(friend?.ownerName ?? "Dots").font(.system(size: 10, weight: .semibold)).lineLimit(1)
            }.accessibilityLabel(friend.map { "\($0.ownerName) is feeling \($0.mood.title)" } ?? "No friend selected")
        } else if let friend {
            HStack(spacing: 8) {
                CompanionView(mood: friend.mood, kind: friend.kind).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.ownerName).font(.system(.headline, design: .rounded)).lineLimit(1)
                    Text(friend.mood.title).font(.caption).lineLimit(1)
                    Text(friend.updatedAt, style: .relative).font(.system(size: 9)).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Label("A little closer", systemImage: "heart.fill").font(.headline)
                Text("Open Dots to add a friend").font(.caption)
            }
        }
    }
}
