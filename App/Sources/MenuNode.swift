import RaceCore
import SpriteKit

/// Everything shown around a race: the title screen, the start countdown, the pause panel, the
/// results panel and the cup standings. One unit is one art pixel and the origin is the centre of
/// the view.
@MainActor
final class MenuNode: SKNode {
    enum Action {
        case start, toggleSound, newCup, resume, again, title
        /// From the results: bank the result and show the standings. From the standings: ride the next race.
        case next, continueCup
        /// The tap was used up by the menu itself.
        case nothing
    }

    /// What the title screen says about the cup.
    struct TitleInfo {
        var raceNumber: Int
        var trackName: String
        var best: Double?
        var cupsWon: Int
        /// True once the cup has a result, so there is something for "new cup" to throw away.
        var cupUnderWay: Bool
        var soundOn: Bool
    }

    private static let placeNames = ["1ST", "2ND", "3RD", "4TH"]
    static let riderNames = ["YOU", "CRIMSON", "VIOLET", "GREEN"]
    /// Centre of the panels above the middle of the view, and the results panel's size.
    private static let panelCentreY: CGFloat = -18
    private static let panelSize = (width: 300, height: 190)
    private static let standingsSize = (width: 260, height: 190)
    /// "Tap to race" blinks this many times a second.
    private static let blinkRate = 1.6

    /// A plate with a label whose text and action change with the situation.
    private struct Button {
        let frame: CGRect
        let plate: SKSpriteNode
        let label: PixelLabel
        var action = Action.nothing

        @MainActor
        mutating func set(_ text: String?, _ action: Action) {
            plate.isHidden = text == nil
            label.isHidden = text == nil
            label.text = text ?? ""
            self.action = action
        }
    }

    private let palette = Palette.shared
    private let dim = SKSpriteNode(color: .black, size: .zero)

    private let titleGroup = SKNode()
    private let cupLine: PixelLabel
    private let trackLine: PixelLabel
    private let prompt: PixelLabel
    private let bestOnTitle: PixelLabel
    private let soundLabel: PixelLabel
    private let newCupLabel: PixelLabel
    /// True after one tap on "new cup"; a second tap there resets the cup.
    private var newCupArmed = false

    private let countLabel: PixelLabel
    private let countCaption: PixelLabel

    private let resultsGroup = SKNode()
    private let placeLabel: PixelLabel
    private let timeLabel: PixelLabel
    private let bestLabel: PixelLabel
    private var rowTimes: [PixelLabel] = []
    private var rowPoints: [PixelLabel] = []
    private var resultButtons: [Button] = []

    private let standingsGroup = SKNode()
    private let standingsCaption: PixelLabel
    private var standingChips: [SKSpriteNode] = []
    private var standingNames: [PixelLabel] = []
    private var standingPoints: [PixelLabel] = []
    private var standingsButtons: [Button] = []

    private let pauseGroup = SKNode()
    private var pauseButtons: [Button] = []
    /// What the pause panel covered, to put back on resume.
    private var hiddenByPause: (dim: Bool, count: Bool) = (true, true)
    private var blinkClock = 0.0

    override init() {
        let p = palette
        cupLine = PixelLabel(colour: p.sand, shadow: p.dark, magnify: 2)
        trackLine = PixelLabel(colour: p.cream, shadow: p.dark, magnify: 3)
        prompt = PixelLabel("TAP TO RACE", colour: p.cream, shadow: p.dark, magnify: 3)
        bestOnTitle = PixelLabel(colour: p.sand, shadow: p.dark, magnify: 2)
        soundLabel = PixelLabel(colour: p.sand, shadow: p.dark, magnify: 2)
        newCupLabel = PixelLabel(colour: p.sand, shadow: p.dark, magnify: 2)
        countLabel = PixelLabel(colour: p.cream, shadow: p.plum, magnify: 12)
        countCaption = PixelLabel(colour: p.cream, shadow: p.dark, magnify: 2)
        placeLabel = PixelLabel(colour: p.cream, shadow: p.dark, magnify: 4)
        timeLabel = PixelLabel(colour: p.sand, magnify: 2)
        bestLabel = PixelLabel(colour: p.orange, magnify: 2)
        standingsCaption = PixelLabel(colour: p.orange, magnify: 2)
        super.init()

        dim.color = Art.colour(p.dark)
        dim.alpha = 0.5
        dim.zPosition = -1
        addChild(dim)

        let logo = PixelLabel("DUNE BIKES", colour: p.cream, shadow: p.hot, magnify: 6)
        logo.position = CGPoint(x: 0, y: 62)
        cupLine.position = CGPoint(x: 0, y: 22)
        trackLine.position = CGPoint(x: 0, y: 0)
        prompt.position = CGPoint(x: 0, y: -36)
        bestOnTitle.position = CGPoint(x: 0, y: -64)
        for node in [logo, cupLine, trackLine, prompt, bestOnTitle, soundLabel, newCupLabel] { titleGroup.addChild(node) }
        addChild(titleGroup)

        countLabel.position = CGPoint(x: 0, y: 24)
        countCaption.position = CGPoint(x: 0, y: 82)
        addChild(countLabel)
        addChild(countCaption)

        buildResults()
        addChild(resultsGroup)
        buildStandings()
        addChild(standingsGroup)
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
        addPanel(to: resultsGroup, width: size.width, height: size.height)
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
            chip.position = CGPoint(x: -126, y: y)
            let label = PixelLabel(name, colour: i == 0 ? p.cream : p.sand, magnify: 2, alignment: .left)
            label.position = CGPoint(x: -114, y: y)
            let time = PixelLabel(colour: i == 0 ? p.cream : p.sand, magnify: 2, alignment: .right)
            time.position = CGPoint(x: 72, y: y)
            let points = PixelLabel(colour: p.orange, magnify: 2, alignment: .right)
            points.position = CGPoint(x: 128, y: y)
            for node in [chip, label, time, points] as [SKNode] {
                node.zPosition = 1
                resultsGroup.addChild(node)
            }
            rowTimes.append(time)
            rowPoints.append(points)
        }
        resultButtons = [addButton(to: resultsGroup, x: -58, y: -72, width: 132),
                         addButton(to: resultsGroup, x: 82, y: -72, width: 76)]
    }

    private func buildStandings() {
        let p = palette
        let size = MenuNode.standingsSize
        standingsGroup.position = CGPoint(x: 0, y: MenuNode.panelCentreY)
        addPanel(to: standingsGroup, width: size.width, height: size.height)
        let heading = PixelLabel("DUNE CUP", colour: p.cream, shadow: p.dark, magnify: 4)
        heading.position = CGPoint(x: 0, y: 70)
        standingsCaption.position = CGPoint(x: 0, y: 44)
        for node in [heading, standingsCaption] {
            node.zPosition = 1
            standingsGroup.addChild(node)
        }
        for i in 0..<MenuNode.riderNames.count {
            let y = CGFloat(18 - i * 18)
            let rank = PixelLabel("\(i + 1)", colour: p.sand, magnify: 2)
            rank.position = CGPoint(x: -104, y: y)
            let chip = SKSpriteNode(color: .white, size: CGSize(width: 8, height: 8))
            chip.position = CGPoint(x: -84, y: y)
            let name = PixelLabel(colour: p.cream, magnify: 2, alignment: .left)
            name.position = CGPoint(x: -72, y: y)
            let points = PixelLabel(colour: p.cream, magnify: 2, alignment: .right)
            points.position = CGPoint(x: 106, y: y)
            for node in [rank, chip, name, points] as [SKNode] {
                node.zPosition = 1
                standingsGroup.addChild(node)
            }
            standingChips.append(chip)
            standingNames.append(name)
            standingPoints.append(points)
        }
        standingsButtons = [addButton(to: standingsGroup, x: -48, y: -72, width: 112),
                            addButton(to: standingsGroup, x: 72, y: -72, width: 76)]
    }

    private func buildPause() {
        let p = palette
        addPanel(to: pauseGroup, width: 180, height: 158)
        let heading = PixelLabel("PAUSED", colour: p.cream, shadow: p.dark, magnify: 4)
        heading.position = CGPoint(x: 0, y: 50)
        heading.zPosition = 1
        pauseGroup.addChild(heading)
        pauseButtons = [(Action.resume, "RESUME", CGFloat(14)), (.again, "RESTART", -18), (.title, "MENU", -50)].map {
            var button = addButton(to: pauseGroup, x: 0, y: $0.2, width: 132)
            button.set($0.1, $0.0)
            return button
        }
    }

    private func addPanel(to group: SKNode, width: Int, height: Int) {
        let p = palette
        let panel = SKSpriteNode(texture: MenuNode.box(width: width, height: height, fill: p.plum, border: p.cream,
                                                       outline: p.dark))
        panel.size = CGSize(width: width, height: height)
        group.addChild(panel)
    }

    /// An orange plate with dark text, centred on (x, y) in `group`.
    private func addButton(to group: SKNode, x: CGFloat, y: CGFloat, width: Int) -> Button {
        let p = palette
        let frame = CGRect(x: x - CGFloat(width) / 2, y: y - 12, width: CGFloat(width), height: 24)
        let plate = SKSpriteNode(texture: MenuNode.box(width: width, height: 24, fill: p.orange, border: p.cream,
                                                       outline: p.dark))
        plate.size = frame.size
        plate.position = CGPoint(x: frame.midX, y: frame.midY)
        plate.zPosition = 1
        let label = PixelLabel(colour: p.dark, magnify: 2)
        label.position = plate.position
        label.zPosition = 2
        group.addChild(plate)
        group.addChild(label)
        return Button(frame: frame, plate: plate, label: label)
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
        soundLabel.position = CGPoint(x: 100, y: -size.height / 2 + 26)
        newCupLabel.position = CGPoint(x: -100, y: -size.height / 2 + 26)
    }

    func hide() {
        dim.isHidden = true
        titleGroup.isHidden = true
        countLabel.isHidden = true
        countCaption.isHidden = true
        resultsGroup.isHidden = true
        standingsGroup.isHidden = true
        pauseGroup.isHidden = true
    }

    func showTitle(_ info: TitleInfo) {
        hide()
        dim.isHidden = false
        titleGroup.isHidden = false
        cupLine.text = "DUNE CUP - RACE \(info.raceNumber)/\(Cup.rounds.count)"
        trackLine.text = info.trackName
        var facts: [String] = []
        if let best = info.best { facts.append("BEST \(HUDNode.format(time: best))") }
        if info.cupsWon > 0 { facts.append("CUPS WON \(info.cupsWon)") }
        bestOnTitle.text = facts.joined(separator: "   ")
        soundLabel.text = info.soundOn ? "SOUND ON" : "SOUND OFF"
        newCupArmed = false
        newCupLabel.text = "NEW CUP"
        newCupLabel.isHidden = !info.cupUnderWay
        blinkClock = 0
    }

    /// `text` is "3", "2", "1" or "GO!"; nil clears it. `caption` is a small line above it.
    func showCountdown(_ text: String?, caption: String? = nil) {
        hide()
        countLabel.isHidden = text == nil
        countLabel.text = text ?? ""
        countCaption.isHidden = caption == nil
        countCaption.text = caption ?? ""
    }

    /// `lastRace` is true for the cup's final race.
    func showResults(for race: Race, best: Double?, newBest: Bool, lastRace: Bool) {
        hide()
        dim.isHidden = false
        resultsGroup.isHidden = false
        let place = race.position(of: 0)
        placeLabel.text = "\(MenuNode.placeNames[min(place, 4) - 1]) PLACE"
        timeLabel.text = "TIME \(HUDNode.format(time: race.time))"
        if place > Cup.worstPlaceToGoOn {
            bestLabel.text = "TOP \(Cup.worstPlaceToGoOn) TO GO ON"
            resultButtons[0].set("RETRY", .again)
            resultButtons[1].set("MENU", .title)
        } else {
            bestLabel.text = newBest ? "NEW BEST!" : best.map { "BEST \(HUDNode.format(time: $0))" } ?? ""
            resultButtons[0].set(lastRace ? "FINISH CUP" : "NEXT RACE", .next)
            resultButtons[1].set("RETRY", .again)
        }
        updateResults(for: race)
    }

    /// Fills in each rider's time as they cross the line, and the points their place is worth.
    func updateResults(for race: Race) {
        for (i, bike) in race.bikes.enumerated() where i < rowTimes.count {
            rowTimes[i].text = bike.finishTime.map { HUDNode.format(time: $0) } ?? "..."
            rowPoints[i].text = "+\(Cup.points[min(race.position(of: i), Cup.points.count) - 1])"
        }
    }

    /// The table after a race. `raceNumber` is the race just banked; when `final`, the cup is over.
    func showStandings(_ cup: Cup, raceNumber: Int, final: Bool) {
        hide()
        dim.isHidden = false
        standingsGroup.isHidden = false
        let order = cup.standings, totals = cup.totals
        if final {
            standingsCaption.text = order[0] == 0 ? "YOU WIN THE CUP!" : "\(MenuNode.riderNames[order[0]]) WINS THE CUP"
            standingsButtons[0].set("NEW CUP", .title)
            standingsButtons[1].set(nil, .nothing)
        } else {
            standingsCaption.text = "AFTER RACE \(raceNumber) OF \(Cup.rounds.count)"
            standingsButtons[0].set("CONTINUE", .continueCup)
            standingsButtons[1].set("MENU", .title)
        }
        for (row, rider) in order.enumerated() {
            standingChips[row].color = HUDNode.riderColours[rider]
            standingNames[row].text = MenuNode.riderNames[rider]
            standingPoints[row].text = "\(totals[rider])"
        }
    }

    /// Puts the pause panel over whatever is showing.
    func showPause() {
        guard pauseGroup.isHidden else { return }
        hiddenByPause = (dim.isHidden, countLabel.isHidden)
        dim.isHidden = false
        countLabel.isHidden = true
        countCaption.isHidden = true
        pauseGroup.isHidden = false
    }

    func hidePause() {
        guard !pauseGroup.isHidden else { return }
        pauseGroup.isHidden = true
        dim.isHidden = hiddenByPause.dim
        countLabel.isHidden = hiddenByPause.count
        countCaption.isHidden = hiddenByPause.count || countCaption.text.isEmpty
    }

    func update(elapsed: Double) {
        guard !titleGroup.isHidden else { return }
        blinkClock += elapsed
        prompt.isHidden = Int(blinkClock * MenuNode.blinkRate * 2) % 2 == 1
    }

    /// What a tap at `point` (in this node's coordinates) asks for, if anything.
    func action(at point: CGPoint) -> Action? {
        func pressed(_ buttons: [Button], in group: SKNode, slack: CGFloat) -> Action? {
            let local = CGPoint(x: point.x - group.position.x, y: point.y - group.position.y)
            return buttons.first { !$0.plate.isHidden && $0.frame.insetBy(dx: -6, dy: -slack).contains(local) }?.action
        }
        if !pauseGroup.isHidden { return pressed(pauseButtons, in: pauseGroup, slack: 4) }
        if !titleGroup.isHidden {
            func near(_ label: PixelLabel) -> Bool {
                !label.isHidden && abs(point.x - label.position.x) < 70 && abs(point.y - label.position.y) < 18
            }
            if near(soundLabel) { return .toggleSound }
            if near(newCupLabel) {
                if newCupArmed { return .newCup }
                newCupArmed = true
                newCupLabel.text = "SURE? TAP AGAIN"
                return .nothing
            }
            return .start
        }
        if !resultsGroup.isHidden { return pressed(resultButtons, in: resultsGroup, slack: 8) }
        if !standingsGroup.isHidden { return pressed(standingsButtons, in: standingsGroup, slack: 8) }
        return nil
    }
}
