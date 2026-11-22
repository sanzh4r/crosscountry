import SpriteKit

/// The colours the controls and menus are drawn in, from the shared palette.
struct Palette {
    let cream: [Int], sand: [Int], orange: [Int], plum: [Int], hot: [Int], dark: [Int]

    static let shared: Palette = {
        let art = ArtInfo.shared
        func named(_ name: String) -> [Int] { art.dash[name] ?? [255, 255, 255] }
        return Palette(cream: named("cream"), sand: named("sand"), orange: named("orange"), plum: named("plum"),
                       hot: named("hot"), dark: art.rock[4])
    }()

    static func mix(_ a: [Int], _ b: [Int], _ t: Double) -> [Int] {
        (0..<3).map { Int((Double(a[$0]) * (1 - t) + Double(b[$0]) * t).rounded()) }
    }
}

/// The left-hand control: a classic cross. Up and down change lane, left and right lean.
/// Drawn pixel by pixel; one unit is one art pixel.
@MainActor
final class DPadNode: SKNode {
    enum Arm: CaseIterable { case up, down, left, right }

    /// Side of one arm, and of the whole cross, in art pixels.
    static let arm = 40
    static let span = arm * 3
    /// Touches this far outside the cross (art pixels) still count, and this close to the centre do not.
    private static let slack: CGFloat = 14
    private static let deadZone: CGFloat = 7

    private var glows: [Arm: SKSpriteNode] = [:]

    var held: Set<Arm> = [] {
        didSet { for (arm, glow) in glows { glow.isHidden = !held.contains(arm) } }
    }

    override init() {
        super.init()
        let body = SKSpriteNode(texture: DPadNode.bodyTexture())
        body.size = CGSize(width: DPadNode.span, height: DPadNode.span)
        addChild(body)
        let a = CGFloat(DPadNode.arm)
        let offsets: [Arm: CGPoint] = [.up: CGPoint(x: 0, y: a), .down: CGPoint(x: 0, y: -a),
                                       .left: CGPoint(x: -a, y: 0), .right: CGPoint(x: a, y: 0)]
        for (arm, offset) in offsets {
            let glow = SKSpriteNode(color: Art.colour(Palette.shared.cream), size: CGSize(width: a - 6, height: a - 6))
            glow.alpha = 0.4
            glow.position = offset
            glow.zPosition = 1
            glow.isHidden = true
            addChild(glow)
            glows[arm] = glow
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The arm under `point` (in the parent's coordinates), judged by direction from the centre so a
    /// thumb sliding around the cross never falls into a gap.
    func arm(at point: CGPoint) -> Arm? {
        let dx = (point.x - position.x) / xScale, dy = (point.y - position.y) / yScale
        let reach = CGFloat(DPadNode.span) / 2 + DPadNode.slack
        guard abs(dx) <= reach, abs(dy) <= reach, max(abs(dx), abs(dy)) >= DPadNode.deadZone else { return nil }
        if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .up : .down
    }

    private static func bodyTexture() -> SKTexture {
        let palette = Palette.shared
        let outline = Pixel(palette.dark), fill = Pixel(palette.plum)
        let light = Pixel(Palette.mix(palette.plum, palette.cream, 0.3))
        let shade = Pixel(Palette.mix(palette.plum, palette.dark, 0.55))
        let arrow = Pixel(palette.cream)
        let a = arm, n = span
        func inside(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < n, y < n else { return false }
            return (a..<2 * a).contains(x) || (a..<2 * a).contains(y)
        }
        var canvas = PixelCanvas(width: n, height: n)
        for y in 0..<n {
            for x in 0..<n where inside(x, y) {
                let edge = !inside(x - 2, y) || !inside(x + 2, y) || !inside(x, y - 2) || !inside(x, y + 2)
                if edge {
                    canvas.set(x, y, outline)
                } else if !inside(x, y - 5) || !inside(x - 5, y) {
                    canvas.set(x, y, light)
                } else if !inside(x, y + 6) || !inside(x + 5, y) {
                    canvas.set(x, y, shade)
                } else {
                    canvas.set(x, y, fill)
                }
            }
        }
        // A dimple in the middle and an arrow on each arm.
        let c = n / 2
        for y in -6...6 { for x in -6...6 where x * x + y * y <= 36 { canvas.set(c + x, c + y, shade) } }
        let tip = a / 2 - 7
        for r in 0..<9 {
            for w in -r...r {
                canvas.set(c + w, tip + r, arrow)               // up
                canvas.set(c + w, n - 1 - tip - r, arrow)       // down
                canvas.set(tip + r, c + w, arrow)               // left
                canvas.set(n - 1 - tip - r, c + w, arrow)       // right
            }
        }
        return canvas.texture()
    }
}

/// A round right-hand button with a raised face that sinks while held.
@MainActor
final class ActionButton: SKNode {
    enum Kind { case gas, boost }

    /// Diameter of the face and depth of the raised edge, in art pixels.
    static let diameter = 46
    private static let depth = 5
    private static let slack: CGFloat = 8

    private let sprite: SKSpriteNode
    private let up: SKTexture
    private let down: SKTexture

    var isHeld = false {
        didSet { if isHeld != oldValue { sprite.texture = isHeld ? down : up } }
    }

    init(_ kind: Kind) {
        up = ActionButton.texture(kind, pressed: false)
        down = ActionButton.texture(kind, pressed: true)
        sprite = SKSpriteNode(texture: up)
        sprite.size = CGSize(width: ActionButton.diameter, height: ActionButton.diameter + ActionButton.depth)
        super.init()
        addChild(sprite)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `point` in the parent's coordinates.
    func hitTest(_ point: CGPoint) -> Bool {
        let dx = (point.x - position.x) / xScale, dy = (point.y - position.y) / yScale
        let reach = CGFloat(ActionButton.diameter) / 2 + ActionButton.slack
        return abs(dx) <= reach && abs(dy) <= reach
    }

    private static let flameRows = ["...#...", "..##...", "..###..", ".####.#", ".######", "#######", "##.####",
                                    "##..###", ".#...#."].map(Array.init)

    private static func texture(_ kind: Kind, pressed: Bool) -> SKTexture {
        let palette = Palette.shared
        let face = kind == .gas ? palette.sand : palette.hot
        let ink = kind == .gas ? palette.plum : palette.cream
        let side = Pixel(Palette.mix(face, palette.dark, 0.55))
        let outline = Pixel(palette.dark)
        let light = Pixel(Palette.mix(face, palette.cream, 0.55))
        let d = diameter, r = Double(d) / 2
        var canvas = PixelCanvas(width: d, height: d + depth)
        func disc(top: Int, _ paint: (Double, Int, Int) -> Pixel?) {
            for y in 0..<d {
                for x in 0..<d {
                    let dx = Double(x) + 0.5 - r, dy = Double(y) + 0.5 - r
                    let distance = (dx * dx + dy * dy).squareRoot()
                    if distance <= r, let pixel = paint(distance, x, y) { canvas.set(x, top + y, pixel) }
                }
            }
        }
        // The raised edge, then the face on top of it (lower when pressed).
        disc(top: depth) { distance, _, _ in distance > r - 2 ? outline : side }
        let top = pressed ? depth - 1 : 0
        disc(top: top) { distance, x, y in
            if distance > r - 2 { return outline }
            if distance > r - 5, x + y < d - 6 { return pressed ? Pixel(face) : light }
            return Pixel(pressed ? Palette.mix(face, palette.dark, 0.18) : face)
        }
        switch kind {
        case .gas:
            let text = "GAS"
            PixelFont.draw(text, into: &canvas, x: (d - PixelFont.width(of: text)) / 2,
                           y: top + (d - PixelFont.glyphHeight) / 2, colour: Pixel(ink))
        case .boost:
            // The dashboard's flame, twice the size.
            let x0 = (d - 14) / 2, y0 = top + (d - 18) / 2
            for (y, row) in flameRows.enumerated() {
                for (x, mark) in row.enumerated() where mark == "#" {
                    let core = (2...4).contains(x) && y >= 5
                    for sy in 0..<2 { for sx in 0..<2 {
                        canvas.set(x0 + x * 2 + sx, y0 + y * 2 + sy, Pixel(core ? palette.sand : ink))
                    } }
                }
            }
        }
        return canvas.texture()
    }
}

/// The pause button in the top corner: two bars and the word PAUSE.
@MainActor
final class PauseButton: SKNode {
    /// Size of the button in art pixels, and how far outside it a touch still counts.
    static let height = 22
    static let width = 19 + PixelFont.width(of: "PAUSE") + 7
    private static let slack: CGFloat = 8

    override init() {
        let palette = Palette.shared
        let w = PauseButton.width, h = PauseButton.height
        var canvas = PixelCanvas(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                let edge = min(x, y, w - 1 - x, h - 1 - y)
                let bar = (7...13).contains(y) && ((7...9).contains(x) || (12...14).contains(x))
                canvas.set(x, y, Pixel(edge < 2 ? palette.dark : edge < 4 || bar ? palette.cream : palette.plum))
            }
        }
        PixelFont.draw("PAUSE", into: &canvas, x: 19, y: 7, colour: Pixel(palette.cream))
        let sprite = SKSpriteNode(texture: canvas.texture())
        sprite.size = CGSize(width: w, height: h)
        super.init()
        addChild(sprite)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `point` in the parent's coordinates.
    func hitTest(_ point: CGPoint) -> Bool {
        let slack = PauseButton.slack
        return abs(point.x - position.x) / xScale <= CGFloat(PauseButton.width) / 2 + slack
            && abs(point.y - position.y) / yScale <= CGFloat(PauseButton.height) / 2 + slack
    }
}
