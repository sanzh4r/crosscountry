import RaceCore
import SpriteKit
import UIKit

/// The dashboard (speed and engine heat), race time as `0:00.0`, and the large final time once finished.
/// Laid out in screen points (its parent is scaled so one unit is one view point).
@MainActor
final class HUDNode: SKNode {
    private static let margin: CGFloat = 16
    private static let dashboardGap: CGFloat = 4

    private let timeLabel = HUDNode.label(size: 26)
    private let finalTimeLabel = HUDNode.label(size: 64)
    private let dashboard = DashboardNode()

    override init() {
        super.init()
        timeLabel.horizontalAlignmentMode = .left
        timeLabel.verticalAlignmentMode = .top
        finalTimeLabel.horizontalAlignmentMode = .center
        finalTimeLabel.verticalAlignmentMode = .center
        finalTimeLabel.isHidden = true
        for node in [timeLabel, finalTimeLabel, dashboard] { addChild(node) }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `viewSize` and `insets` in view points; the node's origin is the centre of the view.
    /// `pixel` is the size of one art pixel in view points, so the dashboard matches the scenery.
    func layout(viewSize: CGSize, insets: UIEdgeInsets, pixel: CGFloat) {
        let left = -viewSize.width / 2 + max(insets.left, HUDNode.margin)
        let top = viewSize.height / 2 - max(insets.top, HUDNode.margin)
        timeLabel.position = CGPoint(x: left, y: top)
        dashboard.setScale(pixel)
        dashboard.position = CGPoint(x: 0, y: viewSize.height / 2 - HUDNode.dashboardGap
                                     - DashboardNode.size.height * pixel / 2)
        finalTimeLabel.position = CGPoint(x: 0, y: 30)
    }

    func update(with race: Race, elapsed: Double) {
        let time = HUDNode.format(time: race.time)
        timeLabel.text = time
        dashboard.update(with: race.bike, elapsed: elapsed)
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
