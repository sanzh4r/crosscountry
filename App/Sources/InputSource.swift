import GameController
import RaceCore
import SpriteKit
import UIKit

/// Merges the hardware keyboard (polled each frame) and the on-screen controls into one `RiderInput`.
/// Keys: Z gas, X boost, left arrow lean back, right arrow lean forward, up and down arrows change
/// lane, R restart, P or escape pause, space or return to start.
@MainActor
final class InputSource {
    private static let margin: CGFloat = 14
    /// View points between the two right-hand buttons, and how much higher the outer one sits.
    private static let buttonGap: CGFloat = 12
    private static let buttonRise: CGFloat = 16
    /// The controls are never drawn smaller than this many view points per art pixel.
    private static let minScale: CGFloat = 1.15
    /// See-through enough that a bike passing behind a control stays visible.
    private static let opacity: CGFloat = 0.72
    /// The cross has empty corners, so it may sit this far into the left safe-area inset (kept for
    /// the screen's rounded corner) without being clipped.
    private static let crossInsetAllowance: CGFloat = 30

    /// The input for the next simulation steps, as of the last `poll()`.
    private(set) var current = RiderInput()
    /// True for exactly one `poll()` per press of R.
    private(set) var restartPressed = false
    /// True for exactly one `poll()` per press of P or escape.
    private(set) var pausePressed = false
    /// True for exactly one `poll()` per press of space, return or Z.
    private(set) var startPressed = false

    /// The controls only show (and only respond) while this is true.
    var controlsVisible = true {
        didSet { for node in [dpad, gasButton, boostButton] as [SKNode] { node.isHidden = !controlsVisible } }
    }

    private let dpad = DPadNode()
    private let gasButton = ActionButton(.gas)
    private let boostButton = ActionButton(.boost)
    private var laneWasHeld = 0
    /// A lane press waits here until the race has taken a step with it.
    private var pendingLane = 0

    /// Active touches by identity, located in the overlay's coordinate space.
    private var touchPoints: [ObjectIdentifier: CGPoint] = [:]
    private var restartWasHeld = false
    private var startWasHeld = false
    private var pauseWasHeld = false

    /// Adds the controls to `overlay`, a camera child whose units are view points with the origin at the centre.
    func attach(to overlay: SKNode) {
        for node in [dpad, gasButton, boostButton] as [SKNode] {
            node.alpha = InputSource.opacity
            overlay.addChild(node)
        }
    }

    /// `pixel` is the size of one art pixel in view points, so the controls match the scenery.
    func layout(viewSize: CGSize, insets: UIEdgeInsets, pixel: CGFloat) {
        let scale = max(pixel, InputSource.minScale)
        let right = viewSize.width / 2 - max(insets.right, InputSource.margin)
        let bottom = -viewSize.height / 2 + max(insets.bottom, InputSource.margin)
        let half = CGFloat(DPadNode.span) * scale / 2
        dpad.setScale(scale)
        let crossLeft = -viewSize.width / 2 + max(insets.left - InputSource.crossInsetAllowance, InputSource.margin)
        dpad.position = CGPoint(x: crossLeft + half, y: bottom + half)
        // Right thumb: gas inside, boost outside and a little higher, close enough to hold both.
        let size = CGFloat(ActionButton.diameter) * scale
        for button in [gasButton, boostButton] { button.setScale(scale) }
        boostButton.position = CGPoint(x: right - size / 2, y: bottom + size / 2 + InputSource.buttonRise)
        gasButton.position = CGPoint(x: right - size * 1.5 - InputSource.buttonGap, y: bottom + size / 2)
    }

    // MARK: Touches (forwarded by the scene)

    func touchesChanged(_ touches: Set<UITouch>, in overlay: SKNode) {
        for touch in touches { touchPoints[ObjectIdentifier(touch)] = touch.location(in: overlay) }
    }

    func touchesEnded(_ touches: Set<UITouch>) {
        for touch in touches { touchPoints[ObjectIdentifier(touch)] = nil }
    }

    /// Call after the race has stepped with `current`, so a lane press is used once.
    func laneChangeTaken() {
        pendingLane = 0
        current.laneChange = 0
    }

    // MARK: Polling

    /// Reads the keyboard and the touch controls; call once per frame before stepping the race.
    func poll() {
        let keyboard = GCKeyboard.coalesced?.keyboardInput
        func key(_ code: GCKeyCode) -> Bool { keyboard?.button(forKeyCode: code)?.isPressed ?? false }

        let points = controlsVisible ? Array(touchPoints.values) : []
        dpad.held = Set(points.compactMap { dpad.arm(at: $0) })
        gasButton.isHeld = points.contains { gasButton.hitTest($0) }
        boostButton.isHeld = points.contains { boostButton.hitTest($0) }

        let back = key(.leftArrow) || dpad.held.contains(.left)
        let forward = key(.rightArrow) || dpad.held.contains(.right)
        // One lane per press: up is toward the far lane (-1), down toward the near one (+1).
        let laneHeld = (key(.downArrow) || dpad.held.contains(.down) ? 1 : 0)
            - (key(.upArrow) || dpad.held.contains(.up) ? 1 : 0)
        if laneHeld != 0 && laneHeld != laneWasHeld { pendingLane = laneHeld }
        laneWasHeld = laneHeld
        current = RiderInput(gas: key(.keyZ) || gasButton.isHeld,
                             boost: key(.keyX) || boostButton.isHeld,
                             lean: (forward ? 1 : 0) - (back ? 1 : 0),
                             laneChange: pendingLane)

        let restartHeld = key(.keyR)
        restartPressed = restartHeld && !restartWasHeld
        restartWasHeld = restartHeld
        let pauseHeld = key(.keyP) || key(.escape)
        pausePressed = pauseHeld && !pauseWasHeld
        pauseWasHeld = pauseHeld
        let startHeld = key(.spacebar) || key(.returnOrEnter) || key(.keyZ)
        startPressed = startHeld && !startWasHeld
        startWasHeld = startHeld
    }
}
