import SpriteKit

/// The game's lettering: a 5 x 7 pixel font drawn in code, so menus, the HUD and the buttons share
/// one retro look. Capitals, digits and a little punctuation.
enum PixelFont {
    static let glyphWidth = 5
    static let glyphHeight = 7
    /// Pixels from one letter's left edge to the next.
    static let advance = 6

    private static let rows: [Character: String] = [
        "A": ".###. #...# #...# ##### #...# #...# #...#", "B": "####. #...# #...# ####. #...# #...# ####.",
        "C": ".#### #.... #.... #.... #.... #.... .####", "D": "####. #...# #...# #...# #...# #...# ####.",
        "E": "##### #.... #.... ####. #.... #.... #####", "F": "##### #.... #.... ####. #.... #.... #....",
        "G": ".#### #.... #.... #.### #...# #...# .###.", "H": "#...# #...# #...# ##### #...# #...# #...#",
        "I": "##### ..#.. ..#.. ..#.. ..#.. ..#.. #####", "J": "..### ...#. ...#. ...#. ...#. #..#. .##..",
        "K": "#...# #..#. #.#.. ##... #.#.. #..#. #...#", "L": "#.... #.... #.... #.... #.... #.... #####",
        "M": "#...# ##.## #.#.# #.#.# #...# #...# #...#", "N": "#...# ##..# #.#.# #..## #...# #...# #...#",
        "O": ".###. #...# #...# #...# #...# #...# .###.", "P": "####. #...# #...# ####. #.... #.... #....",
        "Q": ".###. #...# #...# #...# #.#.# #..#. .##.#", "R": "####. #...# #...# ####. #.#.. #..#. #...#",
        "S": ".#### #.... #.... .###. ....# ....# ####.", "T": "##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
        "U": "#...# #...# #...# #...# #...# #...# .###.", "V": "#...# #...# #...# #...# #...# .#.#. ..#..",
        "W": "#...# #...# #...# #.#.# #.#.# ##.## #...#", "X": "#...# #...# .#.#. ..#.. .#.#. #...# #...#",
        "Y": "#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..", "Z": "##### ....# ...#. ..#.. .#... #.... #####",
        "0": ".###. #...# #..## #.#.# ##..# #...# .###.", "1": "..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.",
        "2": ".###. #...# ....# ...#. ..#.. .#... #####", "3": "####. ....# ....# .###. ....# ....# ####.",
        "4": "...#. ..##. .#.#. #..#. ##### ...#. ...#.", "5": "##### #.... ####. ....# ....# #...# .###.",
        "6": ".###. #.... #.... ####. #...# #...# .###.", "7": "##### ....# ...#. ..#.. ..#.. ..#.. ..#..",
        "8": ".###. #...# #...# .###. #...# #...# .###.", "9": ".###. #...# #...# .#### ....# ....# .###.",
        ":": "..... ..#.. ..#.. ..... ..#.. ..#.. .....", ".": "..... ..... ..... ..... ..... .##.. .##..",
        "/": "....# ....# ...#. ..#.. .#... #.... #....", "!": "..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#..",
        "+": "..... ..#.. ..#.. ##### ..#.. ..#.. .....", "?": ".###. #...# ....# ...#. ..#.. ..... ..#..",
        "-": "..... ..... ..... ##### ..... ..... .....", ">": "#.... .#... ..#.. ...#. ..#.. .#... #....",
    ]

    private static let glyphs: [Character: [[Bool]]] = rows.mapValues { text in
        text.split(separator: " ").map { $0.map { $0 == "#" } }
    }

    /// Width in pixels of `text` on one line.
    static func width(of text: String) -> Int { max(text.count * advance - 1, 1) }

    /// Draws `text` with its top-left corner at (x, y). Unknown characters leave a gap.
    static func draw(_ text: String, into canvas: inout PixelCanvas, x: Int, y: Int, colour: Pixel) {
        for (i, character) in text.uppercased().enumerated() {
            guard let glyph = glyphs[character] else { continue }
            for (row, line) in glyph.enumerated() {
                for (column, on) in line.enumerated() where on {
                    canvas.set(x + i * advance + column, y + row, colour)
                }
            }
        }
    }
}

/// One line of pixel lettering, with an optional drop shadow one pixel down and right.
/// `magnify` is the size of one font pixel in the parent's units. The sprite is a child, so scaling
/// the label never fights with the size set when the text changes.
@MainActor
final class PixelLabel: SKNode {
    enum Alignment { case left, centre, right }

    private let ink: Pixel
    private let shadow: Pixel?
    private let magnify: CGFloat
    private let sprite = SKSpriteNode()

    var text: String {
        didSet { if text != oldValue { redraw() } }
    }

    init(_ text: String = "", colour: [Int], shadow: [Int]? = nil, magnify: CGFloat, alignment: Alignment = .centre) {
        self.text = text
        ink = Pixel(colour)
        self.shadow = shadow.map { Pixel($0) }
        self.magnify = magnify
        super.init()
        switch alignment {
        case .left: sprite.anchorPoint = CGPoint(x: 0, y: 0.5)
        case .centre: sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        case .right: sprite.anchorPoint = CGPoint(x: 1, y: 0.5)
        }
        addChild(sprite)
        redraw()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    private func redraw() {
        let extra = shadow == nil ? 0 : 1
        var canvas = PixelCanvas(width: PixelFont.width(of: text) + extra, height: PixelFont.glyphHeight + extra)
        if let shadow { PixelFont.draw(text, into: &canvas, x: 1, y: 1, colour: shadow) }
        PixelFont.draw(text, into: &canvas, x: 0, y: 0, colour: ink)
        sprite.texture = canvas.texture()
        sprite.size = CGSize(width: CGFloat(canvas.width) * magnify, height: CGFloat(canvas.height) * magnify)
    }
}
