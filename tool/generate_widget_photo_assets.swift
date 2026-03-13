import AppKit
import Foundation

struct StateConfig {
    let frames: Int
    let duration: Int
    let swing: CGFloat
    let bob: CGFloat
    let phaseOffset: CGFloat
    let swayX: CGFloat
    let secondHarmonic: CGFloat
    let bobHarmonic: CGFloat
    let wet: Bool
    let snow: Bool
    let fog: Bool
    let hot: Bool
    let missing: Bool
    let severe: Bool
}

let canvasSize = CGSize(width: 384, height: 384)
let baseURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("widget_assets/android_widget_png/base.png")
let cutURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("widget_assets/android_widget_png/base_cut.png")
let drawableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("android/app/src/main/res/drawable-nodpi", isDirectory: true)
let sourceRootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("widget_assets/android_widget_png", isDirectory: true)
let drawableXmlURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("android/app/src/main/res/drawable", isDirectory: true)

let stateConfigs: [String: StateConfig] = [
    "calm": .init(frames: 20, duration: 118, swing: 0.010, bob: 0.8, phaseOffset: 0.55, swayX: 5.0, secondHarmonic: 0.12, bobHarmonic: 0.10, wet: false, snow: false, fog: false, hot: false, missing: false, severe: false),
    "windy": .init(frames: 32, duration: 38, swing: 0.120, bob: 3.4, phaseOffset: 0.0, swayX: 10.0, secondHarmonic: 0.18, bobHarmonic: 0.15, wet: false, snow: false, fog: false, hot: false, missing: false, severe: false),
    "rain": .init(frames: 20, duration: 104, swing: 0.018, bob: 1.6, phaseOffset: 0.25, swayX: 5.5, secondHarmonic: 0.13, bobHarmonic: 0.11, wet: false, snow: false, fog: false, hot: false, missing: false, severe: false),
    "snow": .init(frames: 20, duration: 126, swing: 0.013, bob: 1.0, phaseOffset: 1.05, swayX: 4.2, secondHarmonic: 0.10, bobHarmonic: 0.08, wet: false, snow: false, fog: false, hot: false, missing: false, severe: false),
    "fog": .init(frames: 20, duration: 134, swing: 0.009, bob: 0.65, phaseOffset: 1.45, swayX: 3.6, secondHarmonic: 0.08, bobHarmonic: 0.07, wet: false, snow: false, fog: false, hot: false, missing: false, severe: false),
    "heat": .init(frames: 20, duration: 110, swing: 0.015, bob: 1.2, phaseOffset: 0.85, swayX: 4.8, secondHarmonic: 0.12, bobHarmonic: 0.10, wet: false, snow: false, fog: false, hot: false, missing: false, severe: false),
    "typhoon": .init(frames: 18, duration: 70, swing: 0.040, bob: 1.4, phaseOffset: 0.10, swayX: 8.5, secondHarmonic: 0.20, bobHarmonic: 0.16, wet: false, snow: false, fog: false, hot: false, missing: true, severe: false),
    "severe_typhoon": .init(frames: 18, duration: 56, swing: 0.060, bob: 1.9, phaseOffset: 0.35, swayX: 11.0, secondHarmonic: 0.24, bobHarmonic: 0.18, wet: false, snow: false, fog: false, hot: false, missing: true, severe: false),
]

func loadCGImage(_ url: URL) throws -> CGImage {
    guard let image = NSImage(contentsOf: url) else {
        throw NSError(domain: "WeatherStone", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load \(url.path)"])
    }
    var rect = CGRect(origin: .zero, size: image.size)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        throw NSError(domain: "WeatherStone", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage for \(url.path)"])
    }
    return cg
}

func makeTransparent(_ cgImage: CGImage) throws -> CGImage {
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerRow = width * 4
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "WeatherStone", code: 3)
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data else { throw NSError(domain: "WeatherStone", code: 4) }
    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * bytesPerRow) + (x * 4)
            let r = Int(pixels[offset])
            let g = Int(pixels[offset + 1])
            let b = Int(pixels[offset + 2])
            let diff = max(abs(r - g), abs(g - b), abs(r - b))
            if r > 210 && g > 210 && b > 210 && diff < 14 {
                pixels[offset + 3] = 0
            }
        }
    }

    guard let result = context.makeImage() else { throw NSError(domain: "WeatherStone", code: 5) }
    return result
}

func makeContext() -> CGContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    return CGContext(
        data: nil,
        width: Int(canvasSize.width),
        height: Int(canvasSize.height),
        bitsPerComponent: 8,
        bytesPerRow: Int(canvasSize.width) * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func savePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "WeatherStone", code: 6)
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

func drawImage(_ image: CGImage, in context: CGContext, angle: CGFloat, offsetX: CGFloat, offsetY: CGFloat, scale: CGFloat = 1.0) {
    let rect = CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height)
    let anchor = CGPoint(x: canvasSize.width / 2, y: canvasSize.height - 8)
    context.saveGState()
    context.translateBy(x: anchor.x + offsetX, y: anchor.y + offsetY)
    context.rotate(by: angle)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -anchor.x, y: -anchor.y)
    context.draw(image, in: rect)
    context.restoreGState()
}

func addTint(_ context: CGContext, color: NSColor, alpha: CGFloat) {
    context.saveGState()
    context.setFillColor(color.withAlphaComponent(alpha).cgColor)
    context.setBlendMode(.sourceAtop)
    context.fill(CGRect(origin: .zero, size: canvasSize))
    context.restoreGState()
}

func addRain(_ context: CGContext) {
    context.saveGState()
    context.setStrokeColor(NSColor(calibratedRed: 0.63, green: 0.82, blue: 0.97, alpha: 0.70).cgColor)
    context.setLineWidth(3.0)
    let drops: [CGPoint] = [CGPoint(x: 124, y: 118), CGPoint(x: 194, y: 112), CGPoint(x: 260, y: 124)]
    for point in drops {
        context.beginPath()
        context.move(to: point)
        context.addLine(to: CGPoint(x: point.x - 8, y: point.y - 34))
        context.strokePath()
    }
    context.restoreGState()
    addTint(context, color: NSColor(calibratedRed: 0.60, green: 0.78, blue: 0.95, alpha: 1), alpha: 0.12)
}

func addSnow(_ context: CGContext) {
    context.saveGState()
    context.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.94).cgColor)
    let capRects = [
        CGRect(x: 102, y: 114, width: 180, height: 26),
        CGRect(x: 136, y: 104, width: 112, height: 18),
    ]
    for rect in capRects {
        context.fillEllipse(in: rect)
    }
    let puffs = [CGRect(x: 112, y: 106, width: 26, height: 18), CGRect(x: 246, y: 108, width: 24, height: 18)]
    for rect in puffs { context.fillEllipse(in: rect) }
    let flakes: [CGPoint] = [CGPoint(x: 124, y: 116), CGPoint(x: 154, y: 128), CGPoint(x: 214, y: 126), CGPoint(x: 252, y: 116)]
    for point in flakes { context.fillEllipse(in: CGRect(x: point.x, y: point.y, width: 7, height: 7)) }
    context.restoreGState()
}

func addFog(_ context: CGContext) {
    context.saveGState()
    context.setBlendMode(.normal)
    let color = NSColor(calibratedWhite: 1.0, alpha: 0.18).cgColor
    context.setFillColor(color)
    let ellipses = [
        CGRect(x: 62, y: 104, width: 86, height: 72),
        CGRect(x: 118, y: 120, width: 100, height: 74),
        CGRect(x: 188, y: 112, width: 92, height: 68),
        CGRect(x: 108, y: 78, width: 110, height: 80),
        CGRect(x: 172, y: 82, width: 92, height: 72),
    ]
    for rect in ellipses { context.fillEllipse(in: rect) }
    context.restoreGState()
}

func addHeat(_ context: CGContext) {
    addTint(context, color: NSColor(calibratedRed: 0.87, green: 0.38, blue: 0.23, alpha: 1), alpha: 0.18)
    context.saveGState()
    context.setStrokeColor(NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.28, alpha: 0.75).cgColor)
    context.setLineWidth(3)
    for i in 0..<3 {
        let x = CGFloat(150 + i * 26)
        context.beginPath()
        context.move(to: CGPoint(x: x, y: 220))
        context.addCurve(to: CGPoint(x: x + 4, y: 320), control1: CGPoint(x: x - 12, y: 250), control2: CGPoint(x: x + 14, y: 290))
        context.strokePath()
    }
    context.restoreGState()
}

func addCracks(_ context: CGContext) {
    context.saveGState()
    context.setStrokeColor(NSColor(calibratedWhite: 0.96, alpha: 0.75).cgColor)
    context.setLineWidth(1.8)
    let paths = [
        [CGPoint(x: 56, y: 366), CGPoint(x: 126, y: 286), CGPoint(x: 156, y: 220)],
        [CGPoint(x: 302, y: 366), CGPoint(x: 246, y: 280), CGPoint(x: 214, y: 210)],
        [CGPoint(x: 192, y: 316), CGPoint(x: 194, y: 228), CGPoint(x: 186, y: 134)],
        [CGPoint(x: 98, y: 148), CGPoint(x: 160, y: 182), CGPoint(x: 214, y: 192)],
    ]
    for path in paths {
        context.beginPath()
        context.addLines(between: path)
        context.strokePath()
    }
    context.restoreGState()
}

func makeFrame(base: CGImage, cut: CGImage, state: String, config: StateConfig, frameIndex: Int) -> CGImage {
    let t = CGFloat(Double.pi * 2) * CGFloat(frameIndex) / CGFloat(config.frames)
    let swing = config.swing * sin(t + config.phaseOffset) + (config.swing * config.secondHarmonic) * sin((2 * t) - 0.6 + config.phaseOffset)
    let bob = config.bob * sin(t - 0.2 + config.phaseOffset * 0.35) + (config.bob * config.bobHarmonic) * sin((2 * t) + 0.1 + config.phaseOffset)
    let driftX = sin(t + config.phaseOffset) * config.swayX
    let context = makeContext()

    if config.missing {
        drawImage(cut, in: context, angle: swing, offsetX: driftX, offsetY: bob)
    } else {
        drawImage(base, in: context, angle: swing, offsetX: driftX, offsetY: bob)
    }

    if config.wet { addRain(context) }
    if config.snow { addSnow(context) }
    if config.fog { addFog(context) }
    if config.hot { addHeat(context) }
    if config.severe { addCracks(context) }

    return context.makeImage()!
}

func writeAnimationXML(state: String, frames: Int, duration: Int) throws {
    var lines = [
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
        "<animation-list xmlns:android=\"http://schemas.android.com/apk/res/android\"",
        "    android:oneshot=\"false\">",
    ]
    for index in 0..<frames {
        let frameName = String(format: "%02d", index)
        lines.append("    <item android:drawable=\"@drawable/widget_stone_\(state)_frame_\(frameName)\" android:duration=\"\(duration)\" />")
    }
    lines.append("</animation-list>")
    let url = drawableXmlURL.appendingPathComponent("widget_stone_animation_\(state).xml")
    try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
}

let baseImage = try makeTransparent(loadCGImage(baseURL))
let cutImage = try makeTransparent(loadCGImage(cutURL))

for (state, config) in stateConfigs {
    let sourceDir: URL
    if state == "windy" {
        sourceDir = sourceRootURL.appendingPathComponent("windy_sequence", isDirectory: true)
    } else {
        sourceDir = sourceRootURL.appendingPathComponent(state, isDirectory: true)
    }
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

    for index in 0..<config.frames {
        let frame = makeFrame(base: baseImage, cut: cutImage, state: state, config: config, frameIndex: index)
        let name = "widget_stone_\(state)_frame_\(String(format: "%02d", index)).png"
        try savePNG(frame, to: drawableURL.appendingPathComponent(name))
        if state == "windy" {
            try savePNG(frame, to: sourceDir.appendingPathComponent("frame_\(String(format: "%02d", index)).png"))
        }
        if index == 0 {
            let staticName = state == "windy" ? "widget_stone_calm.png" : "widget_stone_\(state).png"
            if state != "windy" {
                try savePNG(frame, to: drawableURL.appendingPathComponent(staticName))
                try savePNG(frame, to: sourceDir.appendingPathComponent("base.png"))
            }
        }
    }

    try writeAnimationXML(state: state, frames: config.frames, duration: config.duration)
}
