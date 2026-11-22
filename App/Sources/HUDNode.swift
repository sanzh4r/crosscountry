import RaceCore
import SpriteKit
import UIKit

/// The dashboard (speed and engine heat), a strip showing every rider's progress along the track, race time as `0:00.0`, place in the race as `2/4`, and the large final time once finished.
/// Laid out in screen points (its parent is scaled so one unit is one view point).
@MainActor
final class HUDNode: SKNode {
    private static let margin: CGFloat = 16
    private static let dashboardGap: CGFloat = 4

    private let timeLabel = HUDNode.label(size: 26)
    private let positionLabel = HUDNode.label(size: 22)
    private let finalTimeLabel = HUDNode.label(size: 64)
    private let dashboard = DashboardNode()

    /// Progress strip under the dashboard, in art pixels: a track line, a finish post, and one marker
    /// per rider in that rider's suit colour (the player's is larger and drawn on top).
    private static let stripWidth: CGFloat = 150
    private static let riderColours: [SKColor] = [
        SKColor(hue: 0.5, saturation: 0.75, brightness: 0.85, alpha: 1),
        SKColor(hue: 0.97, saturation: 0.8, brightness: 0.9, alpha: 1),
        SKColor(hue: 0.76, saturation: 0.6, brightness: 0.95, alpha: 1),
        SKColor(hue: 0.27, saturation: 0.75, brightness: 0.8, alpha: 1)]
    private let strip = SKNode()
    private var markers: [SKSpriteNode] = []

    override init() {
        super.init()
        timeLabel.horizontalAlignmentMode = .left
        timeLabel.verticalAlignmentMode = .top
        positionLabel.horizontalAlignmentMode = .left
        positionLabel.verticalAlignmentMode = .top
        finalTimeLabel.horizontalAlignmentMode = .center
        finalTimeLabel.verticalAlignmentMode = .center
        finalTimeLabel.isHidden = true
        for node in [timeLabel, positionLabel, finalTimeLabel, dashboard, strip] { addChild(node) }
        let colours = ArtInfo.shared.dash
        let line = SKSpriteNode(color: Art.colour(colours["sand"] ?? [0, 0, 0]),
                                size: CGSize(width: HUDNode.stripWidth, height: 2))
        let post = SKSpriteNode(color: Art.colour(colours["cream"] ?? [255, 255, 255]), size: CGSize(width: 2, height: 8))
        post.position = CGPoint(x: HUDNode.stripWidth / 2, y: 0)
        strip.addChild(line)
        strip.addChild(post)
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
        positionLabel.position = CGPoint(x: left, y: top - 32)
        strip.setScale(pixel)
        strip.position = CGPoint(x: 0, y: dashboard.position.y - (DashboardNode.size.height / 2 + 7) * pixel)
        finalTimeLabel.position = CGPoint(x: 0, y: 30)
    }

    func update(with race: Race, elapsed: Double) {
        let time = HUDNode.format(time: race.time)
        timeLabel.text = time
        dashboard.update(with: race.bike, elapsed: elapsed)
        let place = "\(race.position(of: 0))/\(race.bikes.count)"
        positionLabel.text = place
        positionLabel.isHidden = race.bikes.count < 2
        finalTimeLabel.isHidden = !race.bike.finished

        while markers.count < race.bikes.count {
            let own = markers.isEmpty
            let colour = HUDNode.riderColours[markers.count % HUDNode.riderColours.count]
            let marker = SKSpriteNode(color: colour, size: own ? CGSize(width: 5, height: 7) : CGSize(width: 3, height: 5))
            marker.zPosition = own ? 2 : 1
            strip.addChild(marker)
            markers.append(marker)
        }
        for (marker, bike) in zip(markers, race.bikes) {
            let done = min(max(bike.x / race.terrain.finishX, 0), 1)
            marker.position = CGPoint(x: (CGFloat(done) - 0.5) * HUDNode.stripWidth, y: 0)
        }
        finalTimeLabel.text = race.bikes.count < 2 ? time : "\(place)  \(time)"
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
