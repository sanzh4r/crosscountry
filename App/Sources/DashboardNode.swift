import RaceCore
import SpriteKit

/// Digital instrument panel: speed in km/h as lit seven-segment digits, and engine heat as a bar of
/// blocks that fills toward a red zone. The engine cuts out when the bar is full, so from the red
/// zone on the frame flashes red. One unit is one art pixel; the fixed parts come from
/// `art/dash_mock.py export` and the lit parts are drawn here pixel by pixel to match.
@MainActor
final class DashboardNode: SKNode {
    /// Size of the panel art in pixels.
    static let size = CGSize(width: 150, height: 62)

    // Layout inside the panel, in art pixels from its top-left corner (see `digital` in dash_mock.py).
    private static let digitsOrigin = (x: 46, y: 8)
    private static let digitSize = (w: 13, h: 23, thickness: 3, pitch: 17)
    private static let barOrigin = (x: 22, y: 42)
    private static let block = (w: 6, h: 12, pitch: 7, count: 16, redFrom: 11, orangeFrom: 6)
    private static let flameOrigin = (x: 9, y: 43)

    /// Flashes per second once the bar is in its red zone.
    private static let warningRate = 5.0

    private let panel: SKSpriteNode
    private let panelTexture = Art.texture("dash")
    private let warnTexture = Art.texture("dash-warn")
    private let digits = SKSpriteNode()
    private let bar = SKSpriteNode()
    private let flame = SKSpriteNode()
    private var digitCache: [Int: SKTexture] = [:]
    private var barCache: [Int: SKTexture] = [:]
    private var flameCool: SKTexture?
    private var flameHot: SKTexture?
    private var warningClock = 0.0

    private let cream: Pixel
    private let sand: Pixel
    private let orange: Pixel
    private let plum: Pixel
    private let hot: Pixel

    override init() {
        let colours = ArtInfo.shared.dash
        cream = Pixel(colours["cream"]); sand = Pixel(colours["sand"]); orange = Pixel(colours["orange"])
        plum = Pixel(colours["plum"]); hot = Pixel(colours["hot"])
        panel = SKSpriteNode(texture: panelTexture)
        super.init()
        addChild(panel)
        let d = DashboardNode.digitSize, b = DashboardNode.block
        place(digits, x: DashboardNode.digitsOrigin.x, y: DashboardNode.digitsOrigin.y, w: d.pitch * 2 + d.w, h: d.h)
        place(bar, x: DashboardNode.barOrigin.x, y: DashboardNode.barOrigin.y, w: b.pitch * (b.count - 1) + b.w, h: b.h)
        place(flame, x: DashboardNode.flameOrigin.x, y: DashboardNode.flameOrigin.y, w: 7, h: 9)
        flameCool = flameTexture(lit: false)
        flameHot = flameTexture(lit: true)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Puts a sprite of `w` x `h` pixels with its top-left at pixel (x, y) of the panel.
    private func place(_ node: SKSpriteNode, x: Int, y: Int, w: Int, h: Int) {
        node.size = CGSize(width: w, height: h)
        node.position = CGPoint(x: CGFloat(x) + CGFloat(w) / 2 - DashboardNode.size.width / 2,
                                y: DashboardNode.size.height / 2 - CGFloat(y) - CGFloat(h) / 2)
        node.zPosition = 1
        addChild(node)
    }

    /// `elapsed` is simulated seconds since the last update.
    func update(with bike: BikeState, elapsed: Double) {
        let kmh = min(max(Int((bike.speed * 3.6).rounded()), 0), 999)
        if digitCache[kmh] == nil { digitCache[kmh] = digitTexture(kmh) }
        digits.texture = digitCache[kmh]

        let b = DashboardNode.block
        let stalled = bike.stallRemaining > 0
        // A block lights when the heat passes its middle; a cut-out engine shows a full bar.
        let lit = stalled ? b.count : min(Int(bike.heat * Double(b.count) + 0.5), b.count)
        if barCache[lit] == nil { barCache[lit] = barTexture(lit: lit) }
        bar.texture = barCache[lit]

        let inRed = lit > b.redFrom
        warningClock += elapsed
        let flash = stalled || (inRed && Int(warningClock * DashboardNode.warningRate * 2) % 2 == 0)
        panel.texture = flash ? warnTexture : panelTexture
        flame.texture = inRed || stalled ? flameHot : flameCool
    }

    private static let segments: [[Character]] = ["abcdef", "bc", "abged", "abgcd", "fgbc", "afgcd", "afgedc",
                                                  "abc", "abcdefg", "abfgcd"].map(Array.init)

    /// Three right-aligned digits; unlit segments are already in the panel art.
    private func digitTexture(_ value: Int) -> SKTexture {
        let d = DashboardNode.digitSize
        var canvas = PixelCanvas(width: d.pitch * 2 + d.w, height: d.h)
        let text = String(value).compactMap(\.wholeNumberValue)
        let m = d.h / 2, t = d.thickness
        let boxes: [Character: (Int, Int, Int, Int)] = [
            "a": (1, 0, d.w - 2, t - 1), "g": (1, m - 1, d.w - 2, m + 1), "d": (1, d.h - t, d.w - 2, d.h - 1),
            "f": (0, 1, t - 1, m - 1), "b": (d.w - t, 1, d.w - 1, m - 1),
            "e": (0, m + 1, t - 1, d.h - 2), "c": (d.w - t, m + 1, d.w - 1, d.h - 2)]
        for (i, digit) in text.enumerated() {
            let x0 = (3 - text.count + i) * d.pitch
            for segment in DashboardNode.segments[digit] {
                guard let box = boxes[segment] else { continue }
                for y in box.1...box.3 { for x in box.0...box.2 { canvas.set(x0 + x, y, cream) } }
            }
        }
        return canvas.texture()
    }

    private func barTexture(lit: Int) -> SKTexture {
        let b = DashboardNode.block
        var canvas = PixelCanvas(width: b.pitch * (b.count - 1) + b.w, height: b.h)
        for i in 0..<b.count {
            let red = i >= b.redFrom, on = i < lit
            let colour = on ? (red ? hot : i >= b.orangeFrom ? orange : sand) : plum
            for y in 0..<b.h {
                for x in 0..<b.w {
                    let cap = on ? (y == 0 && !red ? cream : colour) : (red && y < 2 ? hot : colour)
                    canvas.set(i * b.pitch + x, y, cap)
                }
            }
        }
        return canvas.texture()
    }

    private static let flameRows = ["...#...", "..##...", "..###..", ".####.#", ".######", "#######", "##.####",
                                    "##..###", ".#...#."].map(Array.init)

    private func flameTexture(lit: Bool) -> SKTexture {
        var canvas = PixelCanvas(width: 7, height: 9)
        for (y, row) in DashboardNode.flameRows.enumerated() {
            for (x, ch) in row.enumerated() where ch == "#" {
                canvas.set(x, y, lit ? (2...4 ~= x && y >= 5 ? sand : hot) : sand)
            }
        }
        return canvas.texture()
    }
}

/// One opaque colour of the palette.
struct Pixel {
    let r: UInt8, g: UInt8, b: UInt8
    init(_ rgb: [Int]?) {
        let c = rgb ?? [0, 0, 0]
        r = UInt8(c[0]); g = UInt8(c[1]); b = UInt8(c[2])
    }
}

/// A small transparent bitmap drawn one pixel at a time; row 0 is the top.
struct PixelCanvas {
    let width: Int, height: Int
    private var bytes: [UInt8]

    init(width: Int, height: Int) {
        self.width = width; self.height = height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
    }

    mutating func set(_ x: Int, _ y: Int, _ p: Pixel) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = (y * width + x) * 4
        bytes[i] = p.r; bytes[i + 1] = p.g; bytes[i + 2] = p.b; bytes[i + 3] = 255
    }

    /// A one-pixel line without smoothing.
    mutating func line(fromX x0: Double, y y0: Double, toX x1: Double, y y1: Double, _ p: Pixel) {
        let steps = max(Int(max(abs(x1 - x0), abs(y1 - y0)).rounded(.up)), 1)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            set(Int((x0 + (x1 - x0) * t).rounded()), Int((y0 + (y1 - y0) * t).rounded()), p)
        }
    }

    @MainActor
    func texture() -> SKTexture {
        // SKTexture(data:) reads rows bottom-up.
        var flipped = [UInt8]()
        flipped.reserveCapacity(bytes.count)
        for row in stride(from: height - 1, through: 0, by: -1) {
            flipped.append(contentsOf: bytes[(row * width * 4)..<((row + 1) * width * 4)])
        }
        let texture = SKTexture(data: Data(flipped), size: CGSize(width: width, height: height))
        texture.filteringMode = .nearest
        return texture
    }
}
