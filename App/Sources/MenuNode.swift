import RaceCore
import SpriteKit

/// Everything shown around a race: the title screen, the start countdown, the pause panel and the
/// results panel.
/// One unit is one art pixel and the origin is the centre of the view.
@MainActor
final class MenuNode: SKNode {
    enum Action { case start, toggleSound, again, title, resume }

    private static let placeNames = ["1ST", "2ND", "3RD", "4TH"]
    private static let riderNames = ["YOU", "CRIMSON", "VIOLET", "GREEN"]
    /// Centre of the results panel above the middle of the view, and its size.
    private static let panelCentreY: CGFloat = -18
    private static let panelSize = (width: 280, height: 190)
    /// "Tap to race" blinks this many times a second.
    private static let blinkRate = 1.6

    private let palette = Palette.shared
    private let dim = SKSpriteNode(color: .black, size: .zero)

    private let titleGroup = SKNode()
    private let prompt: PixelLabel
    private let bestOnTitle: PixelLabel
    private let soundLabel: PixelLabel

    private let countLabel: PixelLabel

    private let resultsGroup = SKNode()
    private let placeLabel: PixelLabel
    private let timeLabel: PixelLabel
    private let bestLabel: PixelLabel
    private var rowTimes: [PixelLabel] = []
    private var buttons: [(action: Action, frame: CGRect)] = []

    private let pauseGroup = SKNode()
    private var pauseButtons: [(action: Action, frame: CGRect)] = []
    /// What the pause panel covered, to put back on resume.
    private var hiddenByPause: (dim: Bool, count: Bool) = (true, true)
    private var blinkClock = 0.0

    override init() {
        let p = palette
        prompt = PixelLabel("TAP TO RACE", colour: p.cream, shadow: p.dark, magnify: 3)
        bestOnTitle = PixelLabel(colour: p.sand, shadow: p.dark, magnify: 2)
        soundLabel = PixelLabel(colour: p.sand, shadow: p.dark, magnify: 2)
        countLabel = PixelLabel(colour: p.cream, shadow: p.plum, magnify: 12)
        placeLabel = PixelLabel(colour: p.cream, shadow: p.dark, magnify: 4)
        timeLabel = PixelLabel(colour: p.sand, magnify: 2)
        bestLabel = PixelLabel(colour: p.orange, magnify: 2)
        super.init()

        dim.color = Art.colour(p.dark)
        dim.alpha = 0.5
        dim.zPosition = -1
        addChild(dim)

        let logo = PixelLabel("DUNE BIKES", colour: p.cream, shadow: p.hot, magnify: 6)
        logo.position = CGPoint(x: 0, y: 52)
        prompt.position = CGPoint(x: 0, y: -8)
        bestOnTitle.position = CGPoint(x: 0, y: -40)
        for node in [logo, prompt, bestOnTitle, soundLabel] { titleGroup.addChild(node) }
        addChild(titleGroup)

        countLabel.position = CGPoint(x: 0, y: 24)
        addChild(countLabel)

        buildResults()
        addChild(resultsGroup)
        buildPause()
        pauseGroup.zPosition = 3
        addChild(pauseGroup)
        hide()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    private func buildResults() {
        let p = palette
        let size = MenuNode.panelSize
        resultsGroup.position = CGPoint(x: 0, y: MenuNode.panelCentreY)
        let panel = SKSpriteNode(texture: MenuNode.box(width: size.width, height: size.height, fill: p.plum,
                                                       border: p.cream, outline: p.dark))
        panel.size = CGSize(width: size.width, height: size.height)
        resultsGroup.addChild(panel)
        placeLabel.position = CGPoint(x: 0, y: 70)
        timeLabel.position = CGPoint(x: 0, y: 44)
        bestLabel.position = CGPoint(x: 0, y: 26)
        for node in [placeLabel, timeLabel, bestLabel] {
            node.zPosition = 1
            resultsGroup.addChild(node)
        }
        for (i, name) in MenuNode.riderNames.enumerated() {
            let y = CGFloat(4 - i * 17)
            let chip = SKSpriteNode(color: HUDNode.riderColours[i], size: CGSize(width: 8, height: 8))
            chip.position = CGPoint(x: -104, y: y)
            let label = PixelLabel(name, colour: i == 0 ? p.cream : p.sand, magnify: 2, alignment: .left)
            label.position = CGPoint(x: -92, y: y)
            let time = PixelLabel(colour: i == 0 ? p.cream : p.sand, magnify: 2, alignment: .right)
            time.position = CGPoint(x: 108, y: y)
            for node in [chip, label, time] as [SKNode] {
                node.zPosition = 1
                resultsGroup.addChild(node)
            }
            rowTimes.append(time)
        }
        buttons = [(Action.again, "RACE AGAIN", CGFloat(-58), 132), (.title, "MENU", CGFloat(82), 76)].map {
            ($0.0, addButton($0.1, to: resultsGroup, x: $0.2, y: -72, width: $0.3))
        }
    }

    private func buildPause() {
        let p = palette
        let panel = SKSpriteNode(texture: MenuNode.box(width: 180, height: 158, fill: p.plum, border: p.cream,
                                                       outline: p.dark))
        panel.size = CGSize(width: 180, height: 158)
        pauseGroup.addChild(panel)
        let heading = PixelLabel("PAUSED", colour: p.cream, shadow: p.dark, magnify: 4)
        heading.position = CGPoint(x: 0, y: 50)
        heading.zPosition = 1
        pauseGroup.addChild(heading)
        pauseButtons = [(Action.resume, "RESUME", CGFloat(14)), (.again, "RESTART", -18), (.title, "MENU", -50)].map {
            ($0.0, addButton($0.1, to: pauseGroup, x: 0, y: $0.2, width: 132))
        }
    }

    /// An orange plate with dark text, centred on (x, y) in `group`; returns its frame there.
    private func addButton(_ text: String, to group: SKNode, x: CGFloat, y: CGFloat, width: Int) -> CGRect {
        let p = palette
        let frame = CGRect(x: x - CGFloat(width) / 2, y: y - 12, width: CGFloat(width), height: 24)
        let plate = SKSpriteNode(texture: MenuNode.box(width: width, height: 24, fill: p.orange, border: p.cream,
                                                       outline: p.dark))
        plate.size = frame.size
        plate.position = CGPoint(x: frame.midX, y: frame.midY)
        plate.zPosition = 1
        let label = PixelLabel(text, colour: p.dark, magnify: 2)
        label.position = plate.position
        label.zPosition = 2
        group.addChild(plate)
        group.addChild(label)
        return frame
    }

    /// A filled box with a dark outline and a border inside it.
    private static func box(width: Int, height: Int, fill: [Int], border: [Int], outline: [Int]) -> SKTexture {
        var canvas = PixelCanvas(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let edge = min(x, y, width - 1 - x, height - 1 - y)
                canvas.set(x, y, Pixel(edge < 2 ? outline : edge < 4 ? border : fill))
            }
        }
        return canvas.texture()
    }

    /// `size` is the visible area in art pixels.
    func layout(size: CGSize) {
        dim.size = CGSize(width: size.width + 4, height: size.height + 4)
        soundLabel.position = CGPoint(x: 0, y: -size.height / 2 + 26)
    }

    func hide() {
        dim.isHidden = true
        titleGroup.isHidden = true
        countLabel.isHidden = true
        resultsGroup.isHidden = true
        pauseGroup.isHidden = true
    }

    /// Puts the pause panel over whatever is showing.
    func showPause() {
        guard pauseGroup.isHidden else { return }
        hiddenByPause = (dim.isHidden, countLabel.isHidden)
        dim.isHidden = false
        countLabel.isHidden = true
        pauseGroup.isHidden = false
    }

    func hidePause() {
        guard !pauseGroup.isHidden else { return }
        pauseGroup.isHidden = true
        dim.isHidden = hiddenByPause.dim
        countLabel.isHidden = hiddenByPause.count
    }

    func showTitle(best: Double?, soundOn: Bool) {
        hide()
        dim.isHidden = false
        titleGroup.isHidden = false
        bestOnTitle.text = best.map { "BEST \(HUDNode.format(time: $0))" } ?? ""
        soundLabel.text = soundOn ? "SOUND ON" : "SOUND OFF"
        blinkClock = 0
    }

    /// `text` is "3", "2", "1" or "GO!"; nil clears it.
    func showCountdown(_ text: String?) {
        hide()
        countLabel.isHidden = text == nil
        countLabel.text = text ?? ""
    }

    func showResults(for race: Race, best: Double?, newBest: Bool) {
        hide()
        dim.isHidden = false
        resultsGroup.isHidden = false
        let place = race.position(of: 0)
        placeLabel.text = "\(MenuNode.placeNames[min(place, 4) - 1]) PLACE"
        timeLabel.text = "TIME \(HUDNode.format(time: race.time))"
        bestLabel.text = newBest ? "NEW BEST!" : best.map { "BEST \(HUDNode.format(time: $0))" } ?? ""
        updateResults(for: race)
    }

    /// Fills in each rider's time as they cross the line.
    func updateResults(for race: Race) {
        for (label, bike) in zip(rowTimes, race.bikes) {
            label.text = bike.finishTime.map { HUDNode.format(time: $0) } ?? "..."
        }
    }

    func update(elapsed: Double) {
        guard !titleGroup.isHidden else { return }
        blinkClock += elapsed
        prompt.isHidden = Int(blinkClock * MenuNode.blinkRate * 2) % 2 == 1
    }

    /// What a tap at `point` (in this node's coordinates) asks for, if anything.
    func action(at point: CGPoint) -> Action? {
        if !pauseGroup.isHidden {
            return pauseButtons.first { $0.frame.insetBy(dx: -6, dy: -4).contains(point) }?.action
        }
        if !titleGroup.isHidden {
            let toggle = soundLabel.position
            if abs(point.x - toggle.x) < 70, abs(point.y - toggle.y) < 18 { return .toggleSound }
            return .start
        }
        if !resultsGroup.isHidden {
            let local = CGPoint(x: point.x - resultsGroup.position.x, y: point.y - resultsGroup.position.y)
            return buttons.first { $0.frame.insetBy(dx: -6, dy: -8).contains(local) }?.action
        }
        return nil
    }
}
