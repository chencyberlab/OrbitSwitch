import QuartzCore

/// Builds `CASpringAnimation`s from Apple's designer-facing spring parameters —
/// damping ratio and response ("Designing Fluid Interfaces", WWDC 2018) —
/// instead of the raw mass/stiffness/damping triplet.
///
/// - Damping ratio controls overshoot: `1.0` is critically damped (smooth
///   settle, the default for UI motion); below `1.0` bounces. Bounce is
///   reserved for interactions that carried momentum.
/// - Response is how quickly the value reaches its target, in seconds. It is
///   not a fixed duration: settle time emerges from the parameters, and the
///   spring can be re-targeted mid-flight without a velocity discontinuity.
enum SpringAnimation {
    /// Critically damped: graceful, non-distracting motion for repositioning UI.
    static let defaultDampingRatio = 1.0

    /// Unit-mass conversion: stiffness = (2π / response)²,
    /// damping = 4π · dampingRatio / response. `duration` is pinned to the
    /// resulting settle time so Core Animation never clips the motion early.
    static func make(
        keyPath: String,
        response: Double,
        dampingRatio: Double = defaultDampingRatio
    ) -> CASpringAnimation {
        let response = max(0.05, response)
        let angularFrequency = 2 * Double.pi / response
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = 1
        spring.stiffness = CGFloat(angularFrequency * angularFrequency)
        spring.damping = CGFloat(4 * Double.pi * dampingRatio / response)
        spring.duration = spring.settlingDuration
        return spring
    }
}
