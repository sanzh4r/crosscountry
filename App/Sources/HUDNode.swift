import RaceCore
import SpriteKit
import UIKit

/// Heat bar, race time as `0:00.0`, speed as a whole number, and the large final time once finished.
/// Laid out in screen points (its parent is scaled so one unit is one view point).
@MainActor
final class HUDNode: SKNode {
    private static let margin: CGFloat = 16
    private static let heatBarSize = CGSize(width: 160, height: 12)

    private let timeLabel = HUDNode.label(size: 26)
    private let speedLabel = HUDNode.label(size: 20)
    private let finalTimeLabel = HUDNode.label(size: 64)
    private let heatBackground = SKSpriteNode(color: SKColor(white: 0, alpha: 0.35), size: HUDNode.heatBarSize)
    private let heatFill = SKSpriteNode(color: .orange, size: HUDNode.heatBarSize)

    override init() {
        super.init()
        timeLabel.horizontalAlignmentMode = .left
        timeLabel.verticalAlignmentMode = .top
        speedLabel.horizontalAlignmentMode = .left
        speedLabel.verticalAlignmentMode = .top
        finalTimeLabel.horizontalAlignmentMode = .center
        finalTimeLabel.verticalAlignmentMode = .center
        finalTimeLabel.isHidden = true
        heatBackground.anchorPoint = CGPoint(x: 0, y: 0.5)
        heatFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        heatFill.zPosition = 1
        heatBackground.addChild(heatFill)
        for node in [timeLabel, speedLabel, finalTimeLabel, heatBackground] { addChild(node) }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `viewSize` and `insets` in view points; the node's origin is the centre of the view.
    func layout(viewSize: CGSize, insets: UIEdgeInsets) {
        let left = -viewSize.width / 2 + max(insets.left, HUDNode.margin)
        let top = viewSize.height / 2 - max(insets.top, HUDNode.margin)
        timeLabel.position = CGPoint(x: left, y: top)
        speedLabel.position = CGPoint(x: left, y: top - 32)
        heatBackground.position = CGPoint(x: -HUDNode.heatBarSize.width / 2, y: top - 13)
        finalTimeLabel.position = CGPoint(x: 0, y: 30)
    }

    func update(with race: Race) {
        let time = HUDNode.format(time: race.time)
        timeLabel.text = time
        speedLabel.text = String(Int(race.bike.speed.rounded()))
        let heat = min(max(race.bike.heat, 0), 1)
        heatFill.xScale = heat
        heatFill.color = SKColor(red: 1, green: 0.65 * (1 - heat), blue: 0.1, alpha: 1)
        finalTimeLabel.isHidden = !race.bike.finished
        finalTimeLabel.text = time
    }

    /// `0:00.0`, rounded to the nearest tenth (race.time drifts slightly from summing dt).
    static func format(time: Double) -> String {
        let tenths = Int((max(time, 0) * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }

    private static func label(size: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.fontSize = size
        label.fontColor = .white
        return label
    }
}
