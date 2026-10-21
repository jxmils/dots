import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import CoreText

@main struct Render {
    @MainActor static func save<V: View>(_ view: V, to url: URL, scale: CGFloat = 2) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = scale
        guard let data = renderer.uiImage?.pngData() else { fatalError("Render failed: \(url.lastPathComponent)") }
        try data.write(to: url)
    }
    @MainActor static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/check")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "Brand/Fonts/Nunito-ExtraBold.ttf") as CFURL, .process, nil)
        CompanionArt.directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        if ProcessInfo.processInfo.environment["DOTLINGS_MOTION_PREVIEW"] == "1" {
            let kinds: [CompanionKind] = [.lavender, .blue, .coconut]
            let artwork = kinds.map { kind in
                [CompanionArt.image(.happy, kind: kind)!] + (0..<6).map { CompanionArt.touchImage($0, kind: kind)! }
            }
            let eggs = EggStage.allCases.map { CompanionArt.eggImage($0)! }
            var pet = SpritePlayback(count: 7)
            var egg = SpritePlayback(count: 12, restingFrame: EggStage.awake.rawValue)
            pet.play(CompanionMotion.rub, interval: CompanionMotion.rubInterval, repeats: true, at: 0)
            egg.play([3, 2, 4, 2], interval: 0.11, repeats: true, at: 0)
            for tick in 0..<180 {
                let time = Double(tick) / 60
                if tick == 108 {
                    pet.play([0], interval: 0.24, at: time)
                    egg.play([2], interval: 0.1, at: time)
                }
                if tick == 132 { pet.play(CompanionMotion.tap, interval: CompanionMotion.tapInterval, at: time) }
                let scene = HStack(spacing: 0) {
                    ForEach(0..<3) { index in
                        SpriteCanvas(images: artwork[index], weights: pet.weights(at: time)).frame(width: 240, height: 280)
                    }
                    SpriteCanvas(images: eggs, weights: egg.weights(at: time)).frame(width: 240, height: 280)
                }.background(DotsStyle.paper)
                try save(scene, to: out.appendingPathComponent(String(format: "motion-%03d.png", tick)), scale: 1)
            }
            print("Rendered 180 continuous artwork samples at 60 Hz")
            return
        }
        for kind in CompanionKind.allCases {
            let poses = HStack(spacing: 8) {
                CompanionView(mood: .happy, kind: kind).frame(width: 140, height: 140)
                ForEach(0..<6) { index in
                    if let image = CompanionArt.touchImage(index, kind: kind) {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: 140, height: 140)
                    }
                }
            }.padding(16).background(DotsStyle.paper)
            try save(poses, to: out.appendingPathComponent("touch-\(kind.rawValue).png"), scale: 1)
        }
        let now = Date()
        let friends = [
            Companion(id: "sam", ownerName: "Sam", petName: "Pip", mood: .happy, updatedAt: now.addingTimeInterval(-180), kind: .pillow),
            Companion(id: "mia", ownerName: "Mia", petName: "Luna", mood: .sleepy, updatedAt: now.addingTimeInterval(-900)),
            Companion(id: "leo", ownerName: "Leo", petName: "Bean", mood: .focused, updatedAt: now.addingTimeInterval(-2100), kind: .blue)
        ]
        func state(_ kind: CompanionKind) -> CircleState {
            var collection = CollectionProgress()
            collection.owned = [.lavender, .blue, .pillow]
            if !collection.owned.contains(kind) { collection.owned.append(kind) }
            collection.lastCheckInDay = CheckInDay.number(now)
            collection.streak = 12; collection.bestStreak = 12; collection.totalDays = 12
            collection.earnedMilestones = [5, 10]
            return CircleState(cloudEnabled: true, companion: Companion(id: "me", ownerName: "Jason", petName: kind == .pillow ? "Cloud" : kind.title, mood: .calm, updatedAt: now, kind: kind), friends: friends, pinnedFriendID: "sam", widgetMode: .pinned, lastSyncedAt: now, collection: collection)
        }
        func phone(_ kind: CompanionKind, tab: DotsTab = .home) -> some View {
            let model = CircleModel(previewState: state(kind))
            return ZStack(alignment: .top) {
                DotsStyle.paper
                DotsRoot(tab: tab).environment(model).frame(width: 402, height: 810).offset(y: 42)
                HStack { Text("9:41").font(.system(size: 14, weight: .semibold)); Spacer(); Image(systemName: "wifi"); Image(systemName: "battery.100percent") }
                    .padding(.horizontal, 30).frame(height: 42)
                VStack { Spacer(); Capsule().fill(DotsStyle.ink).frame(width: 130, height: 4).padding(.vertical, 9) }
            }.frame(width: 402, height: 874).clipped()
        }
        for kind in [CompanionKind.lavender, .blue, .pillow, .dusk, .toast, .twinkle, .sprout] { try save(phone(kind), to: out.appendingPathComponent("\(kind.rawValue)-home.png")) }
        try save(phone(.pillow, tab: .friends), to: out.appendingPathComponent("friends.png"))
        try save(phone(.pillow, tab: .widget), to: out.appendingPathComponent("widgets.png"))
        try save(phone(.pillow, tab: .collection), to: out.appendingPathComponent("collection.png"))
        try save(HatchingView(free: true).environment(CircleModel(previewState: CircleState())).frame(width: 402, height: 874), to: out.appendingPathComponent("hatching.png"))
        for stage in [EggStage.awake, .firstCrack, .secondCrack, .lifting, .parting] {
            try save(HatchingView(free: true, previewStage: stage).environment(CircleModel(previewState: CircleState())).frame(width: 402, height: 874),
                     to: out.appendingPathComponent("hatching-stage-\(stage.rawValue).png"))
        }
        let eggFrames = VStack(spacing: 8) {
            ForEach(0..<2) { row in
                HStack(spacing: 8) {
                    ForEach(0..<6) { column in
                        EggArtwork(stage: EggStage(rawValue: row * 6 + column)!).frame(width: 160, height: 160)
                    }
                }
            }
        }.padding(20).background(DotsStyle.paper)
        try save(eggFrames, to: out.appendingPathComponent("egg-sequence.png"), scale: 1)
        try save(HatchingView(free: true, previewRevealed: .coconut).environment(CircleModel(previewState: CircleState())).frame(width: 402, height: 874), to: out.appendingPathComponent("hatch-name.png"))
        let profile = VStack(alignment: .leading, spacing: 22) {
            Text("Your profile").font(DotsStyle.round(30, weight: .bold))
            ProfileDotCard(companion: Companion(id: "me", ownerName: "Jason", petName: "Coco", mood: .happy, updatedAt: now, kind: .coconut))
            Label("Choose my profile Dotling", systemImage: "sparkles").font(DotsStyle.round(16, weight: .bold)).foregroundStyle(DotsStyle.plum)
            Text("Pick any companion you've hatched from your collection.").font(DotsStyle.round(14)).foregroundStyle(DotsStyle.muted)
        }.padding(28).frame(width: 402).background(DotsStyle.paper)
        try save(profile, to: out.appendingPathComponent("profile.png"))
        let catalogue = VStack(alignment: .leading, spacing: 20) {
            Text("Twenty-nine tiny someones.").font(DotsStyle.round(34, weight: .bold))
            Text("One free beginning. Twenty-eight little discoveries.").font(DotsStyle.round(17)).foregroundStyle(DotsStyle.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(180)), count: 5), spacing: 15) {
                ForEach(CompanionKind.allCases) { kind in
                    VStack(spacing: 5) {
                        CompanionView(mood: .happy, kind: kind).frame(width: 166, height: 166)
                        Text(kind.title).font(DotsStyle.round(16, weight: .bold))
                    }.padding(9).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 25))
                }
            }
        }.padding(32).background(DotsStyle.paper).foregroundStyle(DotsStyle.ink)
        try save(catalogue, to: out.appendingPathComponent("all-creatures.png"), scale: 1)
        let additions: [CompanionKind] = [.onion, .cumulus, .bonsai, .droplet, .drizzle, .storm, .bowling, .coffee, .coconut]
        let newCatalogue = VStack(alignment: .leading, spacing: 22) {
            Text("Nine new little someones.").font(DotsStyle.round(32, weight: .bold))
            Text("Their first names. Yours to change.").font(DotsStyle.round(17)).foregroundStyle(DotsStyle.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(230)), count: 3), spacing: 18) {
                ForEach(additions) { kind in
                    VStack(spacing: 4) {
                        CompanionView(mood: .happy, kind: kind).frame(width: 220, height: 220)
                        Text(kind.defaultName).font(DotsStyle.round(20, weight: .bold))
                        Text(kind.title).font(DotsStyle.round(13)).foregroundStyle(DotsStyle.muted)
                    }.padding(12).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 28))
                }
            }
        }.padding(32).background(DotsStyle.paper).foregroundStyle(DotsStyle.ink)
        try save(newCatalogue, to: out.appendingPathComponent("new-creatures.png"), scale: 1)
        let lockPreviews = VStack(alignment: .leading, spacing: 28) {
            Text("Three little ways to stay close.").font(DotsStyle.round(30, weight: .bold))
            HStack(alignment: .center, spacing: 40) {
                VStack(spacing: 20) { FriendWidgetView(friend: friends[0], circular: true).frame(width: 65, height: 65); Text("Circular").font(.caption) }
                VStack(spacing: 20) { FriendWidgetView(friend: friends[0]).frame(width: 190, height: 65); Text("Rectangular").font(.caption) }
                VStack(spacing: 20) { FriendWidgetView(friend: friends[0], inline: true).frame(width: 220, height: 65); Text("Inline").font(.caption) }
            }
        }.padding(36).foregroundStyle(.white).background(DotsStyle.plum)
        try save(lockPreviews, to: out.appendingPathComponent("lock-screen-previews.png"), scale: 2)
        let gallery = VStack(alignment: .leading, spacing: 26) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("dotlings").font(DotsStyle.brand(32))
                    Text("Small friend. Big feelings.").font(DotsStyle.round(20)).foregroundStyle(DotsStyle.muted)
                }
                Spacer()
                Text("APP PREVIEW · SAMPLE FRIENDS").font(DotsStyle.round(10, weight: .semibold)).tracking(1.5).foregroundStyle(DotsStyle.muted)
            }
            HStack(alignment: .top, spacing: 24) {
                phone(.pillow).clipShape(RoundedRectangle(cornerRadius: 38))
                phone(.lavender, tab: .collection).clipShape(RoundedRectangle(cornerRadius: 38))
                phone(.blue, tab: .widget).clipShape(RoundedRectangle(cornerRadius: 38))
            }
        }.padding(36).background(Color(red: 0.92, green: 0.88, blue: 0.94)).foregroundStyle(DotsStyle.ink)
        try save(gallery, to: out.appendingPathComponent("preview.png"), scale: 1)
        let icon = ZStack {
            DotsStyle.lilac
            if let mascot = UIImage(contentsOfFile: "Brand/Mascot.png") {
                Image(uiImage: mascot).resizable().scaledToFit().frame(width: 940, height: 940)
            }
        }.frame(width: 1024, height: 1024)
        let iconDir = URL(fileURLWithPath: "Dots/Assets.xcassets/AppIcon.appiconset")
        try FileManager.default.createDirectory(at: iconDir, withIntermediateDirectories: true)
        let iconRenderer = ImageRenderer(content: icon)
        iconRenderer.scale = 1
        guard let image = iconRenderer.cgImage,
              let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let destination = CGImageDestinationCreateWithURL(iconDir.appendingPathComponent("AppIcon.png") as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Icon renderer unavailable") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        guard let opaque = context.makeImage() else { fatalError("Icon composition failed") }
        CGImageDestinationAddImage(destination, opaque, nil)
        precondition(CGImageDestinationFinalize(destination), "Could not save opaque icon")
        try "{\"images\":[{\"filename\":\"AppIcon.png\",\"idiom\":\"universal\",\"platform\":\"ios\",\"size\":\"1024x1024\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}".write(to: iconDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        print("Rendered app screens, widget previews and app icon")
    }
}
