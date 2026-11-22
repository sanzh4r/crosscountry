import Foundation

extension Track {
    /// The track with `piece` added, or nil when the piece rules do not allow it there.
    public func adding(_ piece: PlacedPiece) -> Track? {
        var copy = self
        copy.pieces.append(piece)
        return (try? copy.validate()) == nil ? nil : copy
    }

    /// Index of the piece covering `cell`: a terrain piece in any lane, otherwise the surface piece
    /// in `lane`, otherwise any surface piece on that cell.
    public func pieceIndex(atCell cell: Int, lane: Int) -> Int? {
        let here = pieces.indices.filter { cell >= pieces[$0].cell && cell < pieces[$0].endCell }
        return here.first { pieces[$0].kind.isTerrain } ?? here.first { pieces[$0].lane == lane } ?? here.first
    }
}

/// A player-built track with its name.
public struct SavedTrack: Codable, Equatable, Sendable {
    public let id: Int
    public var name: String
    public var track: Track
}

/// The player's own tracks, a few at most.
public struct TrackLibrary: Codable, Equatable, Sendable {
    public enum Length: Int, CaseIterable, Sendable {
        case short = 80, medium = 160, long = 260
    }

    public static let maxTracks = 6
    public private(set) var tracks: [SavedTrack] = []
    /// The number the next new track is named with; never reused.
    private var nextNumber = 1

    public init() {}

    public var isFull: Bool { tracks.count >= TrackLibrary.maxTracks }

    /// Adds an empty track of the given length; nil when the library is full.
    public mutating func create(_ length: Length) -> SavedTrack? {
        guard !isFull else { return nil }
        let saved = SavedTrack(id: nextNumber, name: "TRACK \(nextNumber)",
                               track: Track(lengthCells: length.rawValue, pieces: []))
        nextNumber += 1
        tracks.append(saved)
        return saved
    }

    /// Stores a changed layout for the track with `id`; an invalid layout is refused.
    @discardableResult
    public mutating func save(_ track: Track, id: Int) -> Bool {
        guard let index = tracks.firstIndex(where: { $0.id == id }), (try? track.validate()) != nil else { return false }
        tracks[index].track = track
        return true
    }

    public mutating func delete(id: Int) {
        tracks.removeAll { $0.id == id }
    }
}
