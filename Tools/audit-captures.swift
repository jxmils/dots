import Foundation
import Vision
import ImageIO

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let expected = [
    "home": ["how are you", "big feelings"],
    "low": ["coco", "low"],
    "friends": ["your little circle", "sam"],
    "widget": ["lock screen preview"],
    "collection": ["little by little", "29 companions"],
    "hatch": ["warm the shell"],
    "name": ["meet coco"],
    "profile": ["your profile", "coco"]
]
for (name, phrases) in expected.sorted(by: { $0.key < $1.key }) {
    let url = root.appendingPathComponent(name + ".png")
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(url: url).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
    try text.write(to: root.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
    guard !text.contains("open in"), !text.contains("cancel"), phrases.allSatisfy({ text.contains($0) }) else {
        fatalError("Capture did not show the intended unobstructed \(name) screen: \(text)")
    }
    print("Verified native \(name) capture")
}
