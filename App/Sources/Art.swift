import SpriteKit

/// Numbers written by `art/compose.py assets` next to the images, so code and art share one palette.
struct ArtInfo: Decodable, Sendable {
    struct Layer: Decodable, Sendable {
        let parallax: Double
        /// Scene points between the bottom of the visible area and the layer's base line, camera at rest.
        let baseAboveBottom: Double
        /// Rows of desert floor baked into the strip image under its base line.
        let floorRows: Double
        let floor: [Int]
    }

    let sand: [[Int]]
    let rock: [[Int]]
    let sky: [Int]
    /// The brightest colour of the palette.
    let sun: [Int]
    let rideFrames: Int
    let standFrames: Int
    /// Dashboard colours by name: cream, sand, orange, plum, hot.
    let dash: [String: [Int]]
    let layers: [String: Layer]

    static let shared: ArtInfo = {
        guard let url = Bundle.main.url(forResource: "art", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let info = try? JSONDecoder().decode(ArtInfo.self, from: data) else {
            fatalError("art.json is missing from the bundle; run art/compose.py assets")
        }
        return info
    }()
}

enum Art {
    /// A bundled image as a pixel-art texture (no smoothing when scaled).
    @MainActor
    static func texture(_ name: String) -> SKTexture {
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .nearest
        return texture
    }

    static func colour(_ rgb: [Int]) -> SKColor {
        SKColor(red: CGFloat(rgb[0]) / 255, green: CGFloat(rgb[1]) / 255, blue: CGFloat(rgb[2]) / 255, alpha: 1)
    }
}
