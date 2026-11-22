import RaceCore
import SpriteKit
import UIKit

/// The dashboard (speed and engine heat), a strip showing every rider's progress along the track,
/// race time as `0:00.0` and place in the race as `2/4`.
/// Laid out in screen points (its parent is scaled so one unit is one view point).
@MainActor
final class HUDNode: SKNode {
    private static let margin: CGFloat = 16
    private static let dashboardGap: CGFloat = 4

    private let timeLabel = PixelLabel(colour: Palette.shared.cream, shadow: Palette.shared.dark, magnify: 2,
                                       alignment: .left)
    private let positionLabel = PixelLabel(colour: Palette.shared.sand, shadow: Palette.shared.dark, magnify: 2,
                                           alignment: .left)
    private let dashboard = DashboardNode()

    /// Progress strip under the dashboard, in art pixels: a track line, a finish post, and one marker
    /// per rider in that rider's suit colour (the player's is larger and drawn on top).
    private static let stripWidth: CGFloat = 150
    static let riderColours: [SKColor] = [
        SKColor(hue: 0.5, saturation: 0.75, brightness: 0.85, alpha: 1),
        SKColor(hue: 0.97, saturation: 0.8, brightness: 0.9, alpha: 1),
        SKColor(hue: 0.76, saturation: 0.6, brightness: 0.95, alpha: 1),
        SKColor(hue: 0.27, saturation: 0.75, brightness: 0.8, alpha: 1)]
    private let strip = SKNode()
    private var markers: [SKSpriteNode] = []

    override init() {
        super.init()
        for node in [timeLabel, positionLabel, dashboard, strip] as [SKNode] { addChild(node) }
        let palette = Palette.shared
        let line = SKSpriteNode(color: Art.colour(palette.sand), size: CGSize(width: HUDNode.stripWidth, height: 2))
        let post = SKSpriteNode(color: Art.colour(palette.cream), size: CGSize(width: 2, height: 8))
        post.position = CGPoint(x: HUDNode.stripWidth / 2, y: 0)
        strip.addChild(line)
        strip.addChild(post)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `viewSize` and `insets` in view points; the node's origin is the centre of the view.
    /// `pixel` is the size of one art pixel in view points, so the HUD matches the scenery.
    func layout(viewSize: CGSize, insets: UIEdgeInsets, pixel: CGFloat) {
        let left = -viewSize.width / 2 + max(insets.left, HUDNode.margin)
        let top = viewSize.height / 2 - max(insets.top, HUDNode.margin)
        timeLabel.setScale(pixel)
        positionLabel.setScale(pixel)
        timeLabel.position = CGPoint(x: left, y: top - 9 * pixel)
        positionLabel.position = CGPoint(x: left, y: top - 29 * pixel)
        dashboard.setScale(pixel)
        dashboard.position = CGPoint(x: 0, y: viewSize.height / 2 - HUDNode.dashboardGap
                                     - DashboardNode.size.height * pixel / 2)
        strip.setScale(pixel)
        strip.position = CGPoint(x: 0, y: dashboard.position.y - (DashboardNode.size.height / 2 + 7) * pixel)
    }

    func update(with race: Race, elapsed: Double) {
        timeLabel.text = HUDNode.format(time: race.time)
        dashboard.update(with: race.bike, elapsed: elapsed)
        positionLabel.text = "\(race.position(of: 0))/\(race.bikes.count)"
        positionLabel.isHidden = race.bikes.count < 2

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
    }

    /// `0:00.0`, rounded to the nearest tenth (race.time drifts slightly from summing dt).
    static func format(time: Double) -> String {
        let tenths = Int((max(time, 0) * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }
}
