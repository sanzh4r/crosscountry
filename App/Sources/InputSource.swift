import GameController
import RaceCore
import SpriteKit
import UIKit

/// Merges the hardware keyboard (polled each frame) and the on-screen touch buttons into one `RiderInput`.
/// Keys: Z gas, X boost, left arrow lean back, right arrow lean forward, R restart.
@MainActor
final class InputSource {
    private static let buttonDiameter: CGFloat = 72     // view points (at least 64)
    private static let buttonGap: CGFloat = 14
    private static let margin: CGFloat = 16

    /// The input for the next simulation steps, as of the last `poll()`.
    private(set) var current = RiderInput()
    /// True for exactly one `poll()` per press of R or the restart button.
    private(set) var restartPressed = false

    /// The restart button only appears (and only responds) while this is true.
    var showsRestartButton = false {
        didSet { restartButton.isHidden = !showsRestartButton }
    }

    private let leanBackButton = TouchButton(symbol: "arrow.left", diameter: InputSource.buttonDiameter)
    private let leanForwardButton = TouchButton(symbol: "arrow.right", diameter: InputSource.buttonDiameter)
    private let gasButton = TouchButton(symbol: "arrow.up", diameter: InputSource.buttonDiameter)
    private let boostButton = TouchButton(symbol: "flame.fill", diameter: InputSource.buttonDiameter)
    private let restartButton = TouchButton(symbol: "arrow.counterclockwise", diameter: InputSource.buttonDiameter)

    /// Active touches by identity, located in the overlay's coordinate space.
    private var touchPoints: [ObjectIdentifier: CGPoint] = [:]
    private var restartWasHeld = false

    private var allButtons: [TouchButton] {
        [leanBackButton, leanForwardButton, gasButton, boostButton, restartButton]
    }

    init() {
        restartButton.isHidden = true
    }

    /// Adds the buttons to `overlay`, a camera child whose units are view points with the origin at the centre.
    func attach(to overlay: SKNode) {
        for button in allButtons { overlay.addChild(button) }
    }

    func layout(viewSize: CGSize, insets: UIEdgeInsets) {
        let radius = InputSource.buttonDiameter / 2
        let step = InputSource.buttonDiameter + InputSource.buttonGap
        let left = -viewSize.width / 2 + max(insets.left, InputSource.margin) + radius
        let right = viewSize.width / 2 - max(insets.right, InputSource.margin) - radius
        let bottom = -viewSize.height / 2 + max(insets.bottom, InputSource.margin) + radius
        leanBackButton.position = CGPoint(x: left, y: bottom)
        leanForwardButton.position = CGPoint(x: left + step, y: bottom)
        gasButton.position = CGPoint(x: right - step, y: bottom)
        boostButton.position = CGPoint(x: right, y: bottom)
        restartButton.position = CGPoint(x: 0, y: -50)
    }

    // MARK: Touches (forwarded by the scene)

    func touchesChanged(_ touches: Set<UITouch>, in overlay: SKNode) {
        for touch in touches { touchPoints[ObjectIdentifier(touch)] = touch.location(in: overlay) }
    }

    func touchesEnded(_ touches: Set<UITouch>) {
        for touch in touches { touchPoints[ObjectIdentifier(touch)] = nil }
    }

    // MARK: Polling

    /// Reads the keyboard and the touch buttons; call once per frame before stepping the race.
    func poll() {
        let keyboard = GCKeyboard.coalesced?.keyboardInput
        func key(_ code: GCKeyCode) -> Bool { keyboard?.button(forKeyCode: code)?.isPressed ?? false }

        for button in allButtons {
            button.isHeld = !button.isHidden && touchPoints.values.contains { button.hitTest($0) }
        }

        let back = key(.leftArrow) || leanBackButton.isHeld
        let forward = key(.rightArrow) || leanForwardButton.isHeld
        current = RiderInput(gas: key(.keyZ) || gasButton.isHeld,
                             boost: key(.keyX) || boostButton.isHeld,
                             lean: (forward ? 1 : 0) - (back ? 1 : 0))

        let restartHeld = key(.keyR) || restartButton.isHeld
        restartPressed = restartHeld && !restartWasHeld
        restartWasHeld = restartHeld
    }
}

/// A round on-screen button showing an SF Symbol glyph; brighter while held.
@MainActor
final class TouchButton: SKNode {
    private let radius: CGFloat
    private let disc: SKShapeNode

    var isHeld = false {
        didSet { disc.fillColor = SKColor(white: 1, alpha: isHeld ? 0.45 : 0.18) }
    }

    init(symbol: String, diameter: CGFloat) {
        radius = diameter / 2
        disc = SKShapeNode(circleOfRadius: diameter / 2)
        super.init()
        disc.fillColor = SKColor(white: 1, alpha: 0.18)
        disc.strokeColor = SKColor(white: 1, alpha: 0.6)
        disc.lineWidth = 2
        addChild(disc)
        if let texture = TouchButton.glyphTexture(symbol, pointSize: diameter * 0.4) {
            let glyph = SKSpriteNode(texture: texture)
            glyph.zPosition = 1
            addChild(glyph)
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `point` in the parent's coordinate space; the hit area is the button's bounding square.
    func hitTest(_ point: CGPoint) -> Bool {
        abs(point.x - position.x) <= radius && abs(point.y - position.y) <= radius
    }

    /// Renders the symbol in white into a bitmap texture.
    private static func glyphTexture(_ name: String, pointSize: CGFloat) -> SKTexture? {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) else { return nil }
        let image = UIGraphicsImageRenderer(size: symbol.size).image { _ in
            symbol.draw(at: .zero)
        }
        return SKTexture(image: image)
    }
}
