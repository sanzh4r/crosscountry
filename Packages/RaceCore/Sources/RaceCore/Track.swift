import Foundation

public enum PieceKind: String, Codable, Sendable, CaseIterable {
    case smallHill, bigHill, rockRamp, bumps, mud, boostPad

    public var widthCells: Int {
        switch self {
        case .smallHill: 2
        case .bigHill: 4
        case .rockRamp: 3
        case .bumps: 3
        case .mud: 2
        case .boostPad: 1
        }
    }

    /// Peak height in metres; surface pieces (mud, boostPad) have none.
    public var height: Double {
        switch self {
        case .smallHill: 1.5
        case .bigHill: 3.5
        case .rockRamp: 2.5
        case .bumps: 0.5
        case .mud, .boostPad: 0
        }
    }

    public var isTerrain: Bool {
        switch self {
        case .mud, .boostPad: false
        case .smallHill, .bigHill, .rockRamp, .bumps: true
        }
    }
}

public struct PlacedPiece: Codable, Equatable, Sendable {
    public var kind: PieceKind
    public var cell: Int
    public var lane: Int?

    public init(kind: PieceKind, cell: Int, lane: Int? = nil) {
        self.kind = kind
        self.cell = cell
        self.lane = lane
    }

    /// Only call on a piece already known to lie in the build zone; `cell + width` could overflow otherwise.
    var endCell: Int { cell + kind.widthCells }
}

public enum TrackError: Error, Equatable {
    case trackTooShort
    case outsideBuildZone(cell: Int)
    case overlap(cell: Int)
    case noFlatGap(cell: Int)
    case laneRequired(cell: Int), laneNotAllowed(cell: Int), badLane(cell: Int)
}

public struct Track: Codable, Equatable, Sendable {
    public static let cellWidth = 4.0
    public static let startZoneCells = 5
    public static let finishZoneCells = 5
    public static let minLengthCells = 20
    public static let laneCount = 3

    public var lengthCells: Int
    public var pieces: [PlacedPiece]

    public init(lengthCells: Int, pieces: [PlacedPiece]) {
        self.lengthCells = lengthCells
        self.pieces = pieces
    }

    public func validate() throws(TrackError) {
        guard lengthCells >= Track.minLengthCells else { throw .trackTooShort }
        let buildStart = Track.startZoneCells
        let buildEnd = lengthCells - Track.finishZoneCells
        let ordered = pieces.enumerated()
            .sorted { ($0.element.cell, $0.offset) < ($1.element.cell, $1.offset) }
            .map(\.element)

        var previous: [PlacedPiece] = []
        for piece in ordered {
            guard piece.cell >= buildStart, piece.cell <= buildEnd - piece.kind.widthCells else {
                throw .outsideBuildZone(cell: piece.cell)
            }
            if piece.kind.isTerrain {
                if piece.lane != nil { throw .laneNotAllowed(cell: piece.cell) }
            } else {
                guard let lane = piece.lane else { throw .laneRequired(cell: piece.cell) }
                guard (0..<Track.laneCount).contains(lane) else { throw .badLane(cell: piece.cell) }
            }
            for other in previous {
                let sharesCell = piece.cell < other.endCell && other.cell < piece.endCell
                let separateLanes = !piece.kind.isTerrain && !other.kind.isTerrain && piece.lane != other.lane
                if sharesCell && !separateLanes { throw .overlap(cell: piece.cell) }
            }
            if piece.kind.isTerrain, previous.contains(where: { $0.kind.isTerrain && $0.endCell == piece.cell }) {
                throw .noFlatGap(cell: piece.cell)
            }
            previous.append(piece)
        }
    }

    public static func load(from data: Data) throws -> Track {
        let track = try JSONDecoder().decode(Track.self, from: data)
        try track.validate()
        return track
    }
}
