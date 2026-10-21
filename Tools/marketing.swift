import SwiftUI
import UIKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

private let cream = Color(red: 0.98, green: 0.96, blue: 0.93)
private let lilac = Color(red: 0.90, green: 0.85, blue: 0.96)
private let ink = Color(red: 0.20, green: 0.18, blue: 0.26)

private func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
    .system(size: size, weight: weight, design: .rounded)
}

private struct Artwork: View {
    var path: String
    var body: some View {
        if let image = UIImage(contentsOfFile: path) { Image(uiImage: image).resizable().scaledToFit() }
    }
}

private struct Mark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 62, y: 87))
        p.addCurve(to: CGPoint(x: 110, y: 70), control1: CGPoint(x: 55, y: 45), control2: CGPoint(x: 94, y: 53))
        p.addCurve(to: CGPoint(x: 149, y: 72), control1: CGPoint(x: 116, y: 35), control2: CGPoint(x: 148, y: 47))
        p.addCurve(to: CGPoint(x: 221, y: 118), control1: CGPoint(x: 192, y: 59), control2: CGPoint(x: 219, y: 84))
        p.addCurve(to: CGPoint(x: 224, y: 165), control1: CGPoint(x: 245, y: 128), control2: CGPoint(x: 243, y: 160))
        p.addCurve(to: CGPoint(x: 128, y: 218), control1: CGPoint(x: 222, y: 209), control2: CGPoint(x: 188, y: 218))
        p.addCurve(to: CGPoint(x: 27, y: 168), control1: CGPoint(x: 65, y: 218), control2: CGPoint(x: 28, y: 206))
        p.addCurve(to: CGPoint(x: 30, y: 122), control1: CGPoint(x: 5, y: 157), control2: CGPoint(x: 9, y: 130))
        p.addCurve(to: CGPoint(x: 62, y: 87), control1: CGPoint(x: 32, y: 100), control2: CGPoint(x: 43, y: 88))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 256, y: rect.height / 256))
    }
}

private struct BrandBackground: View {
    var body: some View {
        LinearGradient(colors: [cream, lilac.opacity(0.75), cream], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct Header: View {
    var size: CGSize
    var body: some View {
        let wide = size.width / size.height > 2
        ZStack {
            BrandBackground()
            VStack(spacing: wide ? 10 : 30) {
                Text("dotlings").font(.custom("Nunito-ExtraBold", size: wide ? 190 : 330)).tracking(-8)
                Text("Small friend. Big feelings.").font(rounded(wide ? 52 : 86, .medium))
                Artwork(path: "Brand/Hero.png").frame(width: wide ? 1680 : 2900, height: wide ? 1120 : 1933)
            }.foregroundStyle(ink)
        }.frame(width: size.width, height: size.height)
    }
}

private struct Phone: View {
    var path: String
    var width: CGFloat
    var body: some View {
        let height = width * 2868 / 1320
        Artwork(path: path).frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.12))
            .padding(width * 0.014)
            .background(Color(red: 0.18, green: 0.16, blue: 0.22), in: RoundedRectangle(cornerRadius: width * 0.135))
            .shadow(color: ink.opacity(0.16), radius: width * 0.06, x: 0, y: width * 0.035)
    }
}

private struct SearchCreative: View {
    var screen: String?
    var body: some View {
        ZStack {
            BrandBackground()
            HStack(spacing: 80) {
                VStack(alignment: .leading, spacing: 55) {
                    Text("dotlings").font(.custom("Nunito-ExtraBold", size: 132)).foregroundStyle(ink.opacity(0.8))
                    Text("Small friend.\nBig feelings.").font(rounded(196)).tracking(-7).lineSpacing(-15)
                    Text("Hatch a companion.\nShare a little of you.").font(rounded(66, .medium)).lineSpacing(15)
                    Artwork(path: "Brand/Hero.png").frame(width: 1680, height: 1120)
                }.frame(width: 1780, alignment: .leading)
                if let screen { Phone(path: screen, width: 880) }
                else { Artwork(path: "Brand/Mascot.png").frame(width: 1100, height: 1100) }
            }.foregroundStyle(ink)
        }.frame(width: 3840, height: 2560)
    }
}

private struct StoreCard: View {
    var title: String
    var subtitle: String
    var screen: String
    var index: Int
    var body: some View {
        ZStack(alignment: .top) {
            if index.isMultiple(of: 2) { BrandBackground() }
            else { cream }
            VStack(spacing: 0) {
                Text("dotlings").font(.custom("Nunito-ExtraBold", size: 52)).padding(.top, 110)
                Text(title).font(rounded(119)).tracking(-4).lineSpacing(-6)
                    .multilineTextAlignment(.center).frame(height: 300).padding(.top, 55)
                Text(subtitle).font(rounded(40, .medium)).multilineTextAlignment(.center)
                    .frame(width: 1130, height: 115).padding(.top, 12)
                Phone(path: screen, width: 864).padding(.top, 92)
            }.foregroundStyle(ink)
        }.frame(width: 1320, height: 2868).clipped()
    }
}

@main struct Marketing {
    @MainActor static func save<V: View>(_ view: V, to url: URL, transparent: Bool = false, scale: CGFloat = 1) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
                                      bitmapInfo: transparent ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Could not export \(url.lastPathComponent)") }
        if !transparent {
            context.setFillColor(UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let composed = context.makeImage() else { fatalError("Could not compose image") }
        CGImageDestinationAddImage(destination, composed, nil)
        precondition(CGImageDestinationFinalize(destination))
        print("Exported \(url.lastPathComponent): \(image.width) × \(image.height)")
    }

    static func svgPath(_ path: CGPath) -> String {
        var result = ""
        path.applyWithBlock { element in
            let p = element.pointee.points
            func xy(_ n: Int) -> String { String(format: "%.3f %.3f", p[n].x, p[n].y) }
            switch element.pointee.type {
            case .moveToPoint: result += "M" + xy(0)
            case .addLineToPoint: result += "L" + xy(0)
            case .addQuadCurveToPoint: result += "Q" + xy(0) + " " + xy(1)
            case .addCurveToPoint: result += "C" + xy(0) + " " + xy(1) + " " + xy(2)
            case .closeSubpath: result += "Z"
            @unknown default: break
            }
        }
        return result
    }

    static func wordmarkSVG(fill: String) -> (String, CGFloat) {
        let font = CTFontCreateWithName("Nunito-ExtraBold" as CFString, 280, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "dotlings", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) + 24
        var paths = ""
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for i in 0..<count {
                if let p = CTFontCreatePathForGlyph(font, glyphs[i], nil) {
                    paths += "<path transform=\"translate(\(positions[i].x + 12) 0)\" d=\"\(svgPath(p))\"/>"
                }
            }
        }
        return ("<g fill=\"\(fill)\" transform=\"translate(0 290) scale(1 -1)\">\(paths)</g>", width)
    }

    @MainActor static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/launch-kit")
        let captures = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "build/store-captures"
        let fm = FileManager.default
        let screenshotSizes: [(folder: String, width: CGFloat, height: CGFloat)] = [
            ("6.9-inch", 1320, 2868), ("6.5-inch", 1284, 2778),
            ("6.3-inch", 1206, 2622), ("6.1-inch", 1179, 2556)
        ]
        for folder in ["logos", "app-store"] + screenshotSizes.map({ "screenshots/" + $0.folder }) {
            try fm.createDirectory(at: out.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "Brand/Fonts/Nunito-ExtraBold.ttf") as CFURL, .process, nil)
        func writeSVG(_ body: String, width: CGFloat, height: CGFloat, name: String) throws {
            let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(width) \(height)\" role=\"img\" aria-label=\"Dotlings\">\(body)</svg>\n"
            try svg.write(to: out.appendingPathComponent("logos/" + name), atomically: true, encoding: .utf8)
        }
        for (name, color) in [("dark", "#332E42"), ("light", "#FFF9F1")] {
            let (paths, width) = wordmarkSVG(fill: color)
            try writeSVG(paths, width: width, height: 370, name: "wordmark-\(name).svg")
            try save(Text("dotlings").font(.custom("Nunito-ExtraBold", size: 280)).foregroundStyle(name == "dark" ? ink : cream)
                .padding(22), to: out.appendingPathComponent("logos/wordmark-\(name).png"), transparent: true)
        }
        let mark = "<path fill=\"#83C7FF\" d=\"\(svgPath(Mark().path(in: CGRect(x: 0, y: 0, width: 256, height: 256)).cgPath))\"/><g fill=\"#332E42\"><circle cx=\"86\" cy=\"141\" r=\"11\"/><circle cx=\"170\" cy=\"141\" r=\"11\"/><path d=\"M110 166 Q128 190 146 166 Q128 178 110 166Z\"/></g><g fill=\"white\"><circle cx=\"83\" cy=\"137\" r=\"3\"/><circle cx=\"167\" cy=\"137\" r=\"3\"/></g>"
        try writeSVG(mark, width: 256, height: 256, name: "mark-color.svg")
        let (paths, width) = wordmarkSVG(fill: "#332E42")
        try writeSVG("<g transform=\"translate(0 20) scale(1.2)\">\(mark)</g><g transform=\"translate(330 0)\">\(paths)</g>", width: width + 330, height: 370, name: "lockup-color.svg")
        try save(ZStack { lilac; Artwork(path: "Brand/Mascot.png").frame(width: 940, height: 940) }.frame(width: 1024, height: 1024), to: out.appendingPathComponent("logos/app-icon-1024.png"))
        try save(Header(size: CGSize(width: 5244, height: 2950)), to: out.appendingPathComponent("app-store/universal-5244x2950.png"))
        try save(Header(size: CGSize(width: 3840, height: 1646)), to: out.appendingPathComponent("app-store/header-3840x1646.png"))
        let homePath = captures + "/home.png"
        let screen = fm.fileExists(atPath: homePath) ? homePath : nil
        let search = SearchCreative(screen: screen)
        try save(search, to: out.appendingPathComponent("app-store/search-results-3840x2560.png"))
        try save(search, to: out.appendingPathComponent("app-store/search-results-1920x1280.png"), scale: 0.5)

        let cards = [
            ("home", "Small friend.\nBig feelings.", "A squishy little someone for every kind of day."),
            ("low", "How are you,\nreally?", "Six moods. All of them welcome."),
            ("friends", "A little closer\nto your people.", "Share a feeling with the friends you invite."),
            ("widget", "A tiny hello.\nOn your Lock Screen.", "Pin a friend, or see the latest shared mood."),
            ("collection", "29 little friends.\nOne feels like you.", "Daily check-ins bring new little discoveries."),
            ("hatch", "A little warmth.\nA new beginning.", "Rub the egg. Three gentle taps. Your first hatch is free."),
            ("name", "Meet your\nlittle someone.", "Keep their default name, or make it your own."),
            ("profile", "Your companion.\nYour kind of cute.", "Choose the Dotling your friends will see.")
        ]
        for (index, item) in cards.enumerated() {
            let path = captures + "/" + item.0 + ".png"
            guard fm.fileExists(atPath: path) else { continue }
            let card = StoreCard(title: item.1, subtitle: item.2, screen: path, index: index)
            let name = String(format: "%02d-", index + 1) + item.0 + ".png"
            for size in screenshotSizes {
                let scale = min(size.width / 1320, size.height / 2868)
                let fitted = ZStack { cream; card.scaleEffect(scale) }
                    .frame(width: size.width, height: size.height).clipped()
                try save(fitted, to: out.appendingPathComponent("screenshots/" + size.folder + "/" + name))
            }
        }
        let board = VStack(alignment: .leading, spacing: 38) {
            HStack(spacing: 30) {
                Artwork(path: out.appendingPathComponent("logos/app-icon-1024.png").path)
                    .frame(width: 190, height: 190).clipShape(RoundedRectangle(cornerRadius: 42))
                VStack(alignment: .leading, spacing: 8) {
                    Text("dotlings").font(.custom("Nunito-ExtraBold", size: 84))
                    Text("Little pets. Closer friends.").font(rounded(30, .medium))
                    Text("APP STORE LAUNCH KIT").font(rounded(16, .semibold)).tracking(4).opacity(0.55)
                }
            }
            Artwork(path: out.appendingPathComponent("app-store/header-3840x1646.png").path)
                .frame(width: 1700, height: 729).clipShape(RoundedRectangle(cornerRadius: 36))
            HStack(alignment: .center, spacing: 55) {
                Artwork(path: out.appendingPathComponent("app-store/search-results-1920x1280.png").path)
                    .frame(width: 950, height: 634).clipShape(RoundedRectangle(cornerRadius: 36))
                VStack(alignment: .leading, spacing: 23) {
                    Text("A little world,\nall belonging together.").font(rounded(44))
                    Text("App icon · wordmarks · header\nSearch creative · native app views\nPrivacy · support · listing copy").font(rounded(24, .medium)).lineSpacing(12)
                    HStack(spacing: 18) {
                        ForEach(0..<4) { i in
                            Circle().fill([ink, lilac, cream, Color(red: 0.51, green: 0.78, blue: 1)][i])
                                .frame(width: 70, height: 70).overlay(Circle().stroke(ink.opacity(0.12)))
                        }
                    }
                }
            }
            HStack(spacing: 16) {
                ForEach(Array(cards.enumerated()), id: \.offset) { i, item in
                    let name = String(format: "%02d-", i + 1) + item.0 + ".png"
                    Artwork(path: out.appendingPathComponent("screenshots/6.9-inch/" + name).path)
                        .frame(width: 198, height: 430).clipShape(RoundedRectangle(cornerRadius: 15))
                }
            }
        }.padding(50).background(Color(red: 0.94, green: 0.90, blue: 0.95)).foregroundStyle(ink)
        try save(board, to: out.appendingPathComponent("launch-kit-preview.png"))
        print("LAUNCH ARTWORK EXPORTED")
    }
}
