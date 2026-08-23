import CoreGraphics
import Foundation

/// Keeps a scroll coasting after the fingers lift.
///
/// Without this, scrolling stops dead the instant contact ends, which reads as broken
/// to anyone who has used a phone — the flick is the most basic thing people try on a
/// touchscreen. Velocity is captured at lift and decays geometrically until it falls
/// below a threshold worth rendering.
///
/// Pure and clock-driven by the caller, so the deceleration curve is testable without
/// waiting for anything in real time.
public struct MomentumScroller: Equatable, Sendable {
    /// Fraction of velocity retained per step. Tuned against a 60Hz-ish tick.
    public var deceleration: CGFloat
    /// Below this speed, in points per second, coasting stops.
    public var minimumSpeed: CGFloat
    /// Guard against a flick so fast it would fling the content away.
    public var maximumSpeed: CGFloat

    private var velocityX: CGFloat = 0
    private var velocityY: CGFloat = 0

    public init(deceleration: CGFloat = 0.94,
                minimumSpeed: CGFloat = 12,
                maximumSpeed: CGFloat = 6000) {
        self.deceleration = deceleration
        self.minimumSpeed = minimumSpeed
        self.maximumSpeed = maximumSpeed
    }

    public var isCoasting: Bool { speed >= minimumSpeed }

    private var speed: CGFloat {
        (velocityX * velocityX + velocityY * velocityY).squareRoot()
    }

    /// Starts coasting. A flick slower than `minimumSpeed` simply never starts, so a
    /// deliberate slow scroll ends exactly where the user left it.
    public mutating func begin(velocityX: CGFloat, velocityY: CGFloat) {
        let magnitude = (velocityX * velocityX + velocityY * velocityY).squareRoot()
        guard magnitude >= minimumSpeed else {
            self.velocityX = 0; self.velocityY = 0; return
        }
        let clamp = magnitude > maximumSpeed ? maximumSpeed / magnitude : 1
        self.velocityX = velocityX * clamp
        self.velocityY = velocityY * clamp
    }

    public mutating func stop() {
        velocityX = 0
        velocityY = 0
    }

    /// Advances by `elapsed` seconds, returning the distance to scroll, or nil once
    /// the glide has run out.
    public mutating func step(elapsed: TimeInterval) -> (deltaX: CGFloat, deltaY: CGFloat)? {
        guard isCoasting else { return nil }
        let deltaX = velocityX * CGFloat(elapsed)
        let deltaY = velocityY * CGFloat(elapsed)
        velocityX *= deceleration
        velocityY *= deceleration
        if !isCoasting { velocityX = 0; velocityY = 0 }
        return (deltaX, deltaY)
    }
}
