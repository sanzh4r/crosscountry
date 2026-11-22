import RaceCore
import SpriteKit

/// The track builder's controls and editing state: buttons along the top, a mini-map of the whole
/// track under them, and the six pieces along the bottom to drag onto the track. The track itself
/// is drawn by the scene from `drawnTrack`. One unit is one art pixel; the origin is the centre of
/// the view.
@MainActor
final class BuilderNode: SKNode {
    /// Something the scene has to do.
    enum Request { case exit, save, test, race, delete }

    private static let kinds: [PieceKind] = [.smallHill, .bigHill, .rockRamp, .bumps, .mud, .boostPad]
    private static let itemSize = (width: 48, height: 34)
    private static let itemGap: CGFloat = 4
    private static let mapSize = (width: 320, height: 14)
    /// A finger that moves less than this far (art pixels) has tapped, not dragged.
    private static let tapSlack: CGFloat = 8
    /// Scene points above and below the middle lane's line where a dragged surface piece changes lane.
    private static let laneBand: (far: CGFloat, near: CGFloat) = (16, -10)
    private static let pointsPerMetre = Double(GameScene.pointsPerMetre)

    private struct Button {
        let request: Request?
        let plate: SKSpriteNode
        let label: PixelLabel
        let width: CGFloat
        var frame: CGRect { CGRect(x: plate.position.x - width / 2, y: plate.position.y - 12, width: width, height: 24) }
    }

    private enum Drag {
        case piece(PieceKind)
        case map
        /// A finger on the track: a pan once it moves, a tap if it does not.
        case track(start: CGPoint, scroll: Double, moved: Bool)
    }

    /// The saved layout plus every change made since.
    private(set) var track = Track(lengthCells: Track.minLengthCells, pieces: [])
    /// The track with the piece being dragged shown where it would land.
    private var preview: Track?
    var drawnTrack: Track { preview ?? track }
    /// Goes up whenever `drawnTrack` changes.
    private(set) var revision = 0
    /// Index in `track.pieces` of the selected piece.
    private(set) var selected: Int?
    var selectedPiece: PlacedPiece? { preview == nil ? selected.map { track.pieces[$0] } : nil }
    /// Metres along the track at the centre of the view.
    private(set) var scroll = 0.0
    /// Metres of track the view shows; set by the scene.
    var visibleMetres = 20.0 {
        didSet { clampScroll(); layoutMap() }
    }
    private(set) var unsaved = false
    private var trackName = ""
    private var drag: Drag?
    private var dragTouch: ObjectIdentifier?
    /// The button waiting for a second tap (leaving with unsaved changes, deleting the track).
    private var armed: Request?

    private let palette = Palette.shared
    private var buttons: [Button] = []
    private var removeButton: Button?
    private var items: [SKSpriteNode] = []
    private let ghost = SKSpriteNode()
    private let map = SKSpriteNode()
    private let mapWindow = SKSpriteNode()
    private let status: PixelLabel

    override init() {
        status = PixelLabel(colour: palette.cream, shadow: palette.dark, magnify: 2)
        super.init()
        for (request, text) in [(Request.exit, "EXIT"), (.save, "SAVE"), (.test, "TEST"), (.race, "RACE"), (.delete, "DELETE")] {
            buttons.append(makeButton(text, request: request))
        }
        let remove = makeButton("REMOVE", request: nil)
        removeButton = remove
        for kind in BuilderNode.kinds {
            let item = SKSpriteNode(texture: BuilderNode.icon(kind))
            item.size = CGSize(width: BuilderNode.itemSize.width, height: BuilderNode.itemSize.height)
            items.append(item)
            addChild(item)
        }
        map.size = CGSize(width: BuilderNode.mapSize.width, height: BuilderNode.mapSize.height)
        mapWindow.zPosition = 1
        ghost.size = items[0].size
        ghost.alpha = 0.8
        ghost.zPosition = 5
        ghost.isHidden = true
        for node in [map, mapWindow, ghost, status] as [SKNode] { addChild(node) }
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    private func makeButton(_ text: String, request: Request?) -> Button {
        let width = PixelFont.width(of: text) * 2 + 14
        let plate = SKSpriteNode(texture: MenuNode.box(width: width, height: 24, fill: palette.orange,
                                                       border: palette.cream, outline: palette.dark))
        plate.size = CGSize(width: width, height: 24)
        let label = PixelLabel(text, colour: palette.dark, magnify: 2)
        label.zPosition = 1
        plate.addChild(label)
        addChild(plate)
        return Button(request: request, plate: plate, label: label, width: CGFloat(width))
    }

    /// A palette plate with the piece's outline on a strip of ground.
    private static func icon(_ kind: PieceKind) -> SKTexture {
        let p = Palette.shared
        let w = itemSize.width, h = itemSize.height, ground = h - 8
        var canvas = PixelCanvas(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                let edge = min(x, y, w - 1 - x, h - 1 - y)
                canvas.set(x, y, Pixel(edge < 2 ? p.dark : edge < 3 ? p.cream : p.plum))
            }
        }
        let sand = Pixel(p.sand)
        for x in 5..<(w - 5) { for y in ground..<(ground + 3) { canvas.set(x, y, sand) } }
        func mound(from x0: Int, width: Int, height: Double, _ shape: (Double) -> Double) {
            for i in 0..<width {
                let top = Int((height * shape(Double(i) / Double(width - 1))).rounded())
                for y in 0..<top { canvas.set(x0 + i, ground - 1 - y, sand) }
            }
        }
        let hill: (Double) -> Double = { (1 - cos(2 * .pi * $0)) / 2 }
        switch kind {
        case .smallHill: mound(from: 15, width: 18, height: 7, hill)
        case .bigHill: mound(from: 9, width: 30, height: 17, hill)
        case .rockRamp: mound(from: 11, width: 26, height: 13) { $0 < 0.85 ? $0 / 0.85 : (1 - $0) / 0.15 }
        case .bumps: mound(from: 9, width: 30, height: 5) { (1 - cos(6 * .pi * $0)) / 2 }
        case .mud:
            let mud = Pixel(ArtInfo.shared.sand[4])
            for x in 10..<(w - 10) { for y in ground..<(ground + 3) { canvas.set(x, y, mud) } }
            for x in stride(from: 14, to: w - 12, by: 7) { canvas.set(x, ground - 2, mud); canvas.set(x + 1, ground - 3, mud) }
        case .boostPad:
            PixelFont.draw(">>>", into: &canvas, x: (w - PixelFont.width(of: ">>>")) / 2, y: ground - 10,
                           colour: Pixel(ArtInfo.shared.sun))
        }
        return canvas.texture()
    }

    // MARK: Layout

    /// `size` is the visible area in art pixels; `bottomInset` is the part of it the device keeps clear.
    func layout(size: CGSize, bottomInset: CGFloat) {
        let top = size.height / 2
        let gap: CGFloat = 6
        var x = -(buttons.reduce(0) { $0 + $1.width } + gap * CGFloat(buttons.count - 1)) / 2
        for button in buttons {
            button.plate.position = CGPoint(x: x + button.width / 2, y: top - 18)
            x += button.width + gap
        }
        map.position = CGPoint(x: 0, y: top - 43)
        status.position = CGPoint(x: 0, y: top - 62)
        let itemWidth = CGFloat(BuilderNode.itemSize.width), itemHeight = CGFloat(BuilderNode.itemSize.height)
        let span = itemWidth * CGFloat(items.count) + BuilderNode.itemGap * CGFloat(items.count - 1)
        let bottom = -size.height / 2 + max(bottomInset, 8)
        for (i, item) in items.enumerated() {
            item.position = CGPoint(x: -span / 2 + itemWidth / 2 + CGFloat(i) * (itemWidth + BuilderNode.itemGap),
                                    y: bottom + itemHeight / 2)
        }
        removeButton?.plate.position = CGPoint(x: 0, y: bottom + itemHeight + 18)
        layoutMap()
    }

    /// Height (in this node's units) below which a dragged piece is back over the palette.
    private var paletteTop: CGFloat { (items.first?.position.y ?? 0) + CGFloat(BuilderNode.itemSize.height) / 2 + 2 }
    private var lengthMetres: Double { Double(track.lengthCells) * Track.cellWidth }

    private func layoutMap() {
        let share = min(visibleMetres / lengthMetres, 1)
        let width = max(Int((Double(BuilderNode.mapSize.width) * share).rounded()), 6)
        let height = BuilderNode.mapSize.height + 4
        var canvas = PixelCanvas(width: width, height: height)
        let frame = Pixel(palette.cream)
        for x in 0..<width {
            for y in 0..<height where min(x, y, width - 1 - x, height - 1 - y) < 2 { canvas.set(x, y, frame) }
        }
        mapWindow.texture = canvas.texture()
        mapWindow.size = CGSize(width: width, height: height)
        let centre = (scroll / lengthMetres - 0.5) * Double(BuilderNode.mapSize.width)
        mapWindow.position = CGPoint(x: map.position.x + CGFloat(centre), y: map.position.y)
    }

    private func drawMap() {
        let w = BuilderNode.mapSize.width, h = BuilderNode.mapSize.height
        var canvas = PixelCanvas(width: w, height: h)
        let cells = Double(track.lengthCells)
        func column(_ cell: Int) -> Int { Int(Double(cell) / cells * Double(w)) }
        let ground = Pixel(palette.plum), closed = Pixel(palette.dark), edge = Pixel(palette.cream)
        for x in 0..<w {
            let open = x >= column(Track.startZoneCells) && x < column(track.lengthCells - Track.finishZoneCells)
            for y in 0..<h { canvas.set(x, y, y == 0 || y == h - 1 ? edge : open ? ground : closed) }
        }
        let mud = Pixel(ArtInfo.shared.sand[4]), pad = Pixel(ArtInfo.shared.sun), rise = Pixel(palette.sand)
        for piece in drawnTrack.pieces {
            let from = column(piece.cell), to = max(column(piece.cell + piece.kind.widthCells), from + 1)
            for x in from..<to {
                if let lane = piece.lane {
                    for y in 0..<3 { canvas.set(x, 1 + lane * 4 + y, piece.kind == .mud ? mud : pad) }
                } else {
                    let tall = Int((piece.kind.height / 3.5 * Double(h - 5)).rounded()) + 2
                    for y in 0..<tall { canvas.set(x, h - 2 - y, rise) }
                }
            }
        }
        map.texture = canvas.texture()
    }

    // MARK: Editing

    /// Opens `track` for editing from its start.
    func begin(_ track: Track, name: String) {
        self.track = track
        trackName = name
        preview = nil
        selected = nil
        unsaved = false
        armed = nil
        drag = nil
        dragTouch = nil
        ghost.isHidden = true
        // Start where building starts: the end of the start stretch sits a little in from the left.
        scroll = Double(Track.startZoneCells) * Track.cellWidth + visibleMetres / 2 - 6
        clampScroll()
        changed()
    }

    #if DEBUG
    /// Centre of palette item `index`, for scripted snapshots.
    func debugItemPoint(_ index: Int) -> CGPoint { items[index].position }
    #endif

    func markSaved() {
        unsaved = false
        refresh(note: "SAVED")
    }

    private func clampScroll() {
        let half = visibleMetres / 2
        scroll = lengthMetres <= visibleMetres ? lengthMetres / 2 : min(max(scroll, half - 4), lengthMetres - half + 4)
    }

    /// Call after `drawnTrack` changed.
    private func changed() {
        revision += 1
        drawMap()
        refresh()
    }

    private func refresh(note: String? = nil) {
        layoutMap()
        removeButton?.plate.isHidden = selectedPiece == nil
        for button in buttons {
            switch button.request {
            case .exit: button.label.text = armed == .exit ? "SURE?" : "EXIT"
            case .delete: button.label.text = armed == .delete ? "SURE?" : "DELETE"
            default: break
            }
        }
        if let note {
            status.text = note
        } else if track.pieces.isEmpty {
            status.text = "DRAG A PIECE ONTO THE TRACK"
        } else {
            status.text = "\(trackName) - \(track.pieces.count) PIECES\(unsaved ? " - NOT SAVED" : "")"
        }
    }

    /// The piece a finger at scene point `world` would place.
    private func candidate(_ kind: PieceKind, at world: CGPoint) -> PlacedPiece {
        let cellPoints = Track.cellWidth * BuilderNode.pointsPerMetre
        let cell = Int((Double(world.x) / cellPoints - Double(kind.widthCells) / 2 + 0.5).rounded(.down))
        return PlacedPiece(kind: kind, cell: cell, lane: kind.isTerrain ? nil : lane(at: world))
    }

    private func lane(at world: CGPoint) -> Int {
        world.y > BuilderNode.laneBand.far ? 0 : world.y < BuilderNode.laneBand.near ? 2 : 1
    }

    // MARK: Touches (forwarded by the scene)

    /// `point` is in this node's coordinates, `world` in the scene's.
    func touchBegan(_ touch: ObjectIdentifier, at point: CGPoint, world: CGPoint) -> Request? {
        guard dragTouch == nil else { return nil }
        if let button = buttons.first(where: { $0.frame.insetBy(dx: -3, dy: -6).contains(point) }),
           let request = button.request {
            return press(request)
        }
        armed = nil
        if let remove = removeButton, !remove.plate.isHidden, remove.frame.insetBy(dx: -6, dy: -6).contains(point),
           let index = selected {
            track.pieces.remove(at: index)
            selected = nil
            unsaved = true
            changed()
            return nil
        }
        dragTouch = touch
        if let index = items.firstIndex(where: { $0.frame.insetBy(dx: -2, dy: -4).contains(point) }) {
            drag = .piece(BuilderNode.kinds[index])
            ghost.texture = items[index].texture
            ghost.position = point
            ghost.isHidden = false
            selected = nil
            refresh()
        } else if map.frame.insetBy(dx: -8, dy: -8).contains(point) {
            drag = .map
            scrollMap(to: point)
        } else {
            drag = .track(start: point, scroll: scroll, moved: false)
            refresh()
        }
        return nil
    }

    func touchMoved(_ touch: ObjectIdentifier, at point: CGPoint, world: CGPoint) {
        guard touch == dragTouch, let drag else { return }
        switch drag {
        case .piece(let kind):
            let landed = point.y > paletteTop ? track.adding(candidate(kind, at: world)) : nil
            ghost.position = point
            ghost.isHidden = landed != nil
            if landed != preview {
                preview = landed
                changed()
            }
        case .map:
            scrollMap(to: point)
        case .track(let start, let from, var moved):
            if abs(point.x - start.x) > BuilderNode.tapSlack { moved = true }
            if moved {
                scroll = from - Double(point.x - start.x) / BuilderNode.pointsPerMetre
                clampScroll()
                layoutMap()
            }
            self.drag = .track(start: start, scroll: from, moved: moved)
        }
    }

    func touchEnded(_ touch: ObjectIdentifier, at point: CGPoint, world: CGPoint) {
        guard touch == dragTouch, let drag else { return }
        dragTouch = nil
        self.drag = nil
        ghost.isHidden = true
        switch drag {
        case .piece:
            if let landed = preview {
                track = landed
                preview = nil
                selected = track.pieces.count - 1
                unsaved = true
                changed()
            } else {
                refresh()
            }
        case .map:
            break
        case .track(_, _, let moved):
            guard !moved else { return }
            let cell = Int((Double(world.x) / (Track.cellWidth * BuilderNode.pointsPerMetre)).rounded(.down))
            selected = track.pieceIndex(atCell: cell, lane: lane(at: world))
            refresh()
        }
    }

    private func scrollMap(to point: CGPoint) {
        let share = Double((point.x - map.position.x) / CGFloat(BuilderNode.mapSize.width)) + 0.5
        scroll = share * lengthMetres
        clampScroll()
        layoutMap()
    }

    /// Leaving with unsaved changes and deleting the track both ask for a second tap.
    private func press(_ request: Request) -> Request? {
        let risky = request == .delete || (request == .exit && unsaved)
        if risky && armed != request {
            armed = request
            refresh(note: request == .delete ? "TAP AGAIN TO DELETE THIS TRACK" : "NOT SAVED - TAP AGAIN TO LEAVE")
            return nil
        }
        armed = nil
        refresh()
        return request
    }
}
