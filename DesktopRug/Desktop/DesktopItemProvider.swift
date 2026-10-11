import AppKit
import CoreServices

struct DesktopItem: Equatable, Sendable {
    let name: String
    let url: URL
    let finderPosition: SIMD2<Float>
    let iconSize: Float

    func collision(mainDisplayHeight: Float) -> CollisionMound {
        let center = ClothGeometry.finderPoint(x: finderPosition.x, y: finderPosition.y, mainDisplayHeight: mainDisplayHeight)
        return CollisionMound(center: center, halfExtent: SIMD2(max(35, iconSize * 0.70), max(35, iconSize * 0.68)), height: max(22, iconSize * 0.55))
    }
}

struct DesktopItemSnapshot: Sendable {
    let items: [DesktopItem]
    let arrangement: String
    let skippedPositions: Int
    let desktopDirectory: URL?
}

enum DesktopProviderError: LocalizedError {
    case permissionNeeded
    case permissionDenied
    case unavailable(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .permissionNeeded: return "Connect Finder to allow read-only icon detection."
        case .permissionDenied: return "Finder access was denied. Enable Desktop Rug in System Settings → Privacy & Security → Automation, or use manual mounds."
        case .unavailable(let message), .unsupported(let message): return message
        }
    }
}

protocol DesktopItemProvider {
    func fetchItems() async throws -> DesktopItemSnapshot
}

final class FinderDesktopItemProvider: DesktopItemProvider {
    private let queue = DispatchQueue(label: "dev.desktoprug.finder", qos: .utility)

    static func permissionStatus() -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        guard let descriptor = target.aeDesc else { return OSStatus(errAEEventNotPermitted) }
        return AEDeterminePermissionToAutomateTarget(descriptor, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
    }

    func fetchItems() async throws -> DesktopItemSnapshot {
        try Task.checkCancellation()
        let status = Self.permissionStatus()
        if status == -1744 { throw DesktopProviderError.permissionNeeded }
        if status != noErr { throw DesktopProviderError.permissionDenied }
        let result: DesktopItemSnapshot = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try Self.readFinder()) }
                catch { continuation.resume(throwing: error) }
            }
        }
        try Task.checkCancellation()
        return result
    }

    func requestPermission() async throws {
        try Task.checkCancellation()
        if Self.permissionStatus() == noErr { return }
        let status: OSStatus = await withCheckedContinuation { continuation in
            queue.async {
                let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
                guard let descriptor = target.aeDesc else { continuation.resume(returning: OSStatus(errAEEventNotPermitted));return }
                continuation.resume(returning: AEDeterminePermissionToAutomateTarget(descriptor, AEEventClass(typeWildCard), AEEventID(typeWildCard), true))
            }
        }
        try Task.checkCancellation()
        guard status == noErr else { throw DesktopProviderError.permissionDenied }
    }

    private static func readFinder() throws -> DesktopItemSnapshot {
        // Finder's public dictionary is the only source of positions; this script never sets a file property.
        let source = """
        with timeout of 4 seconds
            tell application id "com.apple.finder"
                set options to icon view options of window of desktop
                set iconPixels to icon size of options
                set currentArrangement to arrangement of options as text
                set desktopFolderPath to POSIX path of (desktop as alias)
                set desktopItems to get items of desktop
                set collected to {}
                repeat with itemRef in desktopItems
                    set p to desktop position of itemRef
                    set end of collected to {name of itemRef as text, URL of itemRef as text, {item 1 of p, item 2 of p}}
                end repeat
                return {iconPixels, currentArrangement, collected, desktopFolderPath}
            end tell
        end timeout
        """
        guard let script = NSAppleScript(source: source) else { throw DesktopProviderError.unavailable("Could not compile the Finder query.") }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if number == -1743 { throw DesktopProviderError.permissionDenied }
            throw DesktopProviderError.unavailable(errorInfo[NSAppleScript.errorMessage] as? String ?? "Finder did not return positions.")
        }
        guard result.numberOfItems == 4, let rows = result.atIndex(3), let sizeDescriptor = result.atIndex(1), let arrangement = result.atIndex(2)?.stringValue, let desktopPath = result.atIndex(4)?.stringValue else {
            throw DesktopProviderError.unavailable("Finder returned an unsupported response.")
        }
        let iconSize = Float(sizeDescriptor.int32Value)
        guard iconSize >= 16 && iconSize <= 256 else { throw DesktopProviderError.unsupported("Finder did not expose a usable icon size. Use manual mounds.") }
        var items: [DesktopItem] = []
        var skipped = 0
        for i in 0..<rows.numberOfItems {
            guard let row = rows.atIndex(i + 1), row.numberOfItems == 3,
                  let name = row.atIndex(1)?.stringValue,
                  let string = row.atIndex(2)?.stringValue, let url = URL(string: string), url.isFileURL,
                  let point = row.atIndex(3), point.numberOfItems == 2,
                  let xd = point.atIndex(1), let yd = point.atIndex(2) else {
                throw DesktopProviderError.unavailable("Finder returned incomplete item data.")
            }
            let x = Float(xd.int32Value), y = Float(yd.int32Value)
            if abs(x) > 30000 || abs(y) > 30000 { skipped += 1; continue }
            items.append(DesktopItem(name: name, url: url, finderPosition: SIMD2(x, y), iconSize: iconSize))
        }
        if !items.isEmpty && items.allSatisfy({ $0.finderPosition == .zero }) {
            throw DesktopProviderError.unsupported("Finder is not exposing displayed icon positions. Stacks and managed desktop layouts can do this; use manual mounds.")
        }
        if items.isEmpty && skipped > 0 { throw DesktopProviderError.unsupported("Finder reports unplaced icons; no automatic geometry is available.") }
        return DesktopItemSnapshot(items: items, arrangement: arrangement, skippedPositions: skipped, desktopDirectory: URL(fileURLWithPath:desktopPath,isDirectory:true))
    }
}

struct MockDesktopItemProvider: DesktopItemProvider {
    let items: [DesktopItem]
    func fetchItems() async throws -> DesktopItemSnapshot {
        try Task.checkCancellation()
        return DesktopItemSnapshot(items: items, arrangement: "Deterministic test data", skippedPositions: 0, desktopDirectory: nil)
    }
}
