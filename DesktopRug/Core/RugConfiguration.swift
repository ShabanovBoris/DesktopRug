import Foundation

public enum PhysicsQuality: String, Codable, CaseIterable, Sendable {
    case efficient, balanced, detailed
    public var columns: Int { switch self { case .efficient: return 29; case .balanced: return 41; case .detailed: return 57 } }
    public var rows: Int { switch self { case .efficient: return 21; case .balanced: return 29; case .detailed: return 39 } }
    public var iterations: Int { switch self { case .efficient: return 6; case .balanced: return 8; case .detailed: return 10 } }
    public var title: String { rawValue.capitalized }
}

public enum RugTexture: String, Codable, CaseIterable, Sendable {
    case heriz, indigo
    case sovietRed = "soviet-red"
    case sovietFloral = "soviet-floral"

    public var title: String {
        switch self {
        case .heriz: return "Heriz · Garnet"
        case .indigo: return "Isfahan · Indigo"
        case .sovietRed: return "Soviet · Red"
        case .sovietFloral: return "Soviet · Floral"
        }
    }
}

public struct ManualMound: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var x: Float
    public var y: Float
    public var width: Float = 115
    public var depth: Float = 100
    public var height: Float = 40

    public init(x: Float, y: Float, width: Float = 115, depth: Float = 100, height: Float = 40) {
        self.x = x; self.y = y; self.width = width; self.depth = depth; self.height = height
    }
    public var collision: CollisionMound { CollisionMound(center: SIMD2(x, y), halfExtent: SIMD2(width / 2, depth / 2), height: height) }
}

public struct RugConfiguration: Codable, Equatable, Sendable {
    public var width: Float = 640
    public var height: Float = 430
    public var originX: Float?
    public var originY: Float?
    public var rotationDegrees: Float = 0
    public var displayID: UInt32?
    public var texture: RugTexture = .heriz
    public var stiffness: Float = 0.88
    public var bending: Float = 0.36
    public var damping: Float = 0.12
    public var gravity: Float = 980
    public var quality: PhysicsQuality = .balanced
    public var frameRate: Int = 60
    public var highQualityShadows = true
    public var debugCollisions = false
    public var isVisible = true
    public var isLocked = false
    public var finderEnabled = false
    public var manualMounds: [ManualMound] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case width, height, originX, originY, rotationDegrees, displayID, texture, stiffness, bending, damping, gravity
        case quality, frameRate, highQualityShadows, debugCollisions, isVisible, isLocked, finderEnabled, manualMounds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        width = try values.decode(Float.self, forKey: .width)
        height = try values.decode(Float.self, forKey: .height)
        originX = try values.decodeIfPresent(Float.self, forKey: .originX)
        originY = try values.decodeIfPresent(Float.self, forKey: .originY)
        // Configurations saved before rotation support retain every existing setting and start at zero degrees.
        rotationDegrees = try values.decodeIfPresent(Float.self, forKey: .rotationDegrees) ?? 0
        displayID = try values.decodeIfPresent(UInt32.self, forKey: .displayID)
        texture = try values.decode(RugTexture.self, forKey: .texture)
        stiffness = try values.decode(Float.self, forKey: .stiffness)
        bending = try values.decode(Float.self, forKey: .bending)
        damping = try values.decode(Float.self, forKey: .damping)
        gravity = try values.decode(Float.self, forKey: .gravity)
        quality = try values.decode(PhysicsQuality.self, forKey: .quality)
        frameRate = try values.decode(Int.self, forKey: .frameRate)
        highQualityShadows = try values.decode(Bool.self, forKey: .highQualityShadows)
        debugCollisions = try values.decode(Bool.self, forKey: .debugCollisions)
        isVisible = try values.decode(Bool.self, forKey: .isVisible)
        isLocked = try values.decode(Bool.self, forKey: .isLocked)
        finderEnabled = try values.decode(Bool.self, forKey: .finderEnabled)
        manualMounds = try values.decode([ManualMound].self, forKey: .manualMounds)
    }

    public mutating func sanitize() {
        width = width.isFinite ? min(max(width, 280), 1400) : 640
        height = height.isFinite ? min(max(height, 200), 950) : 430
        stiffness = stiffness.isFinite ? min(max(stiffness, 0.4), 1) : 0.88
        bending = bending.isFinite ? min(max(bending, 0.05), 1) : 0.36
        damping = damping.isFinite ? min(max(damping, 0.02), 0.8) : 0.12
        gravity = gravity.isFinite ? min(max(gravity, 100), 2000) : 980
        if let x = originX, !x.isFinite { originX = nil }
        if let y = originY, !y.isFinite { originY = nil }
        rotationDegrees = ClothGeometry.normalizedDegrees(rotationDegrees)
        if ![30, 60, 120].contains(frameRate) { frameRate = 60 }
        manualMounds = Array(manualMounds.filter { $0.x.isFinite && $0.y.isFinite && $0.width.isFinite && $0.depth.isFinite && $0.height.isFinite }.prefix(64))
        for i in manualMounds.indices {
            manualMounds[i].width = min(max(manualMounds[i].width, 20), 300)
            manualMounds[i].depth = min(max(manualMounds[i].depth, 20), 300)
            manualMounds[i].height = min(max(manualMounds[i].height, 1), 150)
        }
    }
}
