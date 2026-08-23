import CoreGraphics
import Foundation

/// Decides which display the touch panel is.
///
/// ## Why this is deliberately strict
///
/// Every prior implementation picked "the first display that isn't the main one."
/// On any three-display setup that silently resolves to the wrong screen — on a
/// MacBook driving an external main monitor, it picks the *built-in* display, and
/// every touch lands on the laptop screen instead of the panel.
///
/// So this resolver never guesses. It tries identity, then name, then exact size,
/// and if none match it returns `nil` rather than picking something plausible.
/// A driver that does nothing is far better than one that clicks in the wrong place.
public struct DisplayResolver: Sendable {
    public struct Criteria: Sendable {
        public var identity: DisplayIdentity?
        public var nameFragments: [String]
        public var expectedSize: CGSize?

        public init(identity: DisplayIdentity? = nil,
                    nameFragments: [String] = ["XENEON", "CineEdge"],
                    expectedSize: CGSize? = CGSize(width: 2560, height: 720)) {
            self.identity = identity
            self.nameFragments = nameFragments
            self.expectedSize = expectedSize
        }
    }

    public enum Resolution: Equatable, Sendable {
        case identity, name, size
    }

    public struct Match: Equatable, Sendable {
        public let display: DisplayDescriptor
        public let how: Resolution
    }

    public let criteria: Criteria
    public init(criteria: Criteria = Criteria()) { self.criteria = criteria }

    public func resolve(among displays: [DisplayDescriptor]) -> Match? {
        // 1. Saved identity — survives reordering, replug, and resolution changes.
        if let identity = criteria.identity,
           let hit = displays.first(where: identity.matches) {
            return Match(display: hit, how: .identity)
        }

        // 2. Display name as reported by the EDID.
        if let hit = displays.first(where: { d in
            guard let name = d.name else { return false }
            return criteria.nameFragments.contains {
                name.range(of: $0, options: .caseInsensitive) != nil
            }
        }) {
            return Match(display: hit, how: .name)
        }

        // 3. Exact native size among external displays. Narrow enough that a
        //    2560x720 strip will not be confused with an ordinary monitor.
        if let size = criteria.expectedSize {
            let candidates = displays.filter {
                !$0.isBuiltin && $0.bounds.width == size.width && $0.bounds.height == size.height
            }
            if candidates.count == 1 {
                return Match(display: candidates[0], how: .size)
            }
        }

        return nil
    }
}
