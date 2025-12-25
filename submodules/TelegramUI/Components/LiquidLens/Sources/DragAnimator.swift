import Foundation
import QuartzCore

public final class DragAnimator {
    public struct Config {
        public let initialValue: CGFloat
        public let valueRange: ClosedRange<CGFloat>
        public let visibilityThreshold: CGFloat
        public let initialScale: CGFloat
        public let pressedScale: CGFloat

        public init(
            initialValue: CGFloat,
            valueRange: ClosedRange<CGFloat>,
            visibilityThreshold: CGFloat = 0.001,
            initialScale: CGFloat = 1,
            pressedScale: CGFloat = 1.5
        ) {
            self.initialValue = initialValue
            self.valueRange = valueRange
            self.visibilityThreshold = visibilityThreshold
            self.initialScale = initialScale
            self.pressedScale = pressedScale
        }
    }

    public struct State {
        public let value: CGFloat
        public let targetValue: CGFloat
        public let progress: CGFloat
        public let pressProgress: CGFloat
        public let scaleX: CGFloat
        public let scaleY: CGFloat
        public let velocity: CGFloat
    }

    public var stateDidChange: ((State) -> Void)?

    private let config: Config

    private var valueSpring: SpringValue
    private var pressSpring: SpringValue
    private var scaleXSpring: SpringValue
    private var scaleYSpring: SpringValue
    private var velocitySpring: SpringValue

    private var targetValue: CGFloat
    private var pressTarget: CGFloat = 0
    private var scaleTarget: CGFloat
    private var releasePending = false

    private var lastTimestamp: CFTimeInterval?
    private var displayLink: CADisplayLink?

    private let velocityTracker = VelocityTracker()

    public init(config: Config) {
        self.config = config
        self.targetValue = config.initialValue.clamped(to: config.valueRange)
        self.valueSpring = SpringValue(
            value: config.initialValue.clamped(to: config.valueRange),
            response: SpringValue.response(fromStiffness: 1000),
            dampingRatio: 1
        )
        self.pressSpring = SpringValue(
            value: 0,
            response: SpringValue.response(fromStiffness: 1000),
            dampingRatio: 1
        )
        self.scaleXSpring = SpringValue(
            value: config.initialScale,
            response: SpringValue.response(fromStiffness: 250),
            dampingRatio: 0.6
        )
        self.scaleYSpring = SpringValue(
            value: config.initialScale,
            response: SpringValue.response(fromStiffness: 250),
            dampingRatio: 0.7
        )
        self.velocitySpring = SpringValue(
            value: 0,
            response: SpringValue.response(fromStiffness: 300),
            dampingRatio: 0.5
        )
        self.scaleTarget = config.initialScale
    }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Public input hooks

    public func updateValue(_ value: CGFloat) {
        targetValue = value.clamped(to: config.valueRange)
        startDisplayLinkIfNeeded()
    }

    public func animateToValue(_ value: CGFloat) {
        targetValue = value.clamped(to: config.valueRange)
        press()
        if velocitySpring.value != 0 {
            velocitySpring.target = 0
            velocitySpring.velocity = 0
        }
        release()
        startDisplayLinkIfNeeded()
    }

    public func press() {
        releasePending = false
        velocityTracker.resetTracking()
        pressTarget = 1
        scaleTarget = config.pressedScale
        startDisplayLinkIfNeeded()
    }

    public func release() {
        releasePending = true
        startDisplayLinkIfNeeded()
    }

    // MARK: - Animation loop

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        lastTimestamp = nil
        displayLink = CADisplayLink(target: self, selector: #selector(step(link:)))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc
    private func step(link: CADisplayLink) {
        let timestamp = link.timestamp
        let dt: CGFloat
        if let last = lastTimestamp {
            dt = CGFloat(timestamp - last)
        } else {
            dt = 1.0 / 60.0
        }
        lastTimestamp = timestamp

        valueSpring.step(toward: targetValue, dt: dt)
        valueSpring.value = valueSpring.value.clamped(to: config.valueRange)

        updateVelocityTracking(timestamp: timestamp)

        pressSpring.step(toward: pressTarget, dt: dt)
        scaleXSpring.step(toward: scaleTarget, dt: dt)
        scaleYSpring.step(toward: scaleTarget, dt: dt)

        velocitySpring.step(toward: velocitySpring.target, dt: dt)

        processReleaseIfNeeded()

        emitState()
        stopDisplayLinkIfIdle()
    }

    private func updateVelocityTracking(timestamp: CFTimeInterval) {
        let millis = Int(timestamp * 1000)
        velocityTracker.addDataPoint(millis, Float(valueSpring.value))
        let rangeWidth = max(config.valueRange.upperBound - config.valueRange.lowerBound, 0.0001)
        let targetVelocity = CGFloat(velocityTracker.calculateVelocity()) / rangeWidth
        velocitySpring.target = targetVelocity
    }

    private func processReleaseIfNeeded() {
        guard releasePending else { return }

        let rangeWidth = config.valueRange.upperBound - config.valueRange.lowerBound
        let threshold = max(config.visibilityThreshold, rangeWidth * 0.025)
        if abs(valueSpring.value - targetValue) <= threshold {
            releasePending = false
            pressTarget = 0
            scaleTarget = config.initialScale
        }
    }

    private func emitState() {
        let progress =
            (valueSpring.value - config.valueRange.lowerBound) /
            (config.valueRange.upperBound - config.valueRange.lowerBound)
        let state = State(
            value: valueSpring.value,
            targetValue: targetValue,
            progress: progress.clamped(to: 0...1),
            pressProgress: pressSpring.value.clamped(to: 0...1),
            scaleX: scaleXSpring.value,
            scaleY: scaleYSpring.value,
            velocity: velocitySpring.value
        )
        stateDidChange?(state)
    }

    private func stopDisplayLinkIfIdle() {
        let valueRest = valueSpring.isAtRest(target: targetValue, threshold: config.visibilityThreshold)
        let pressRest = pressSpring.isAtRest(target: pressTarget, threshold: 0.001)
        let scaleRest =
            scaleXSpring.isAtRest(target: scaleTarget, threshold: 0.001) &&
            scaleYSpring.isAtRest(target: scaleTarget, threshold: 0.001)
        let velocityRest = velocitySpring.isAtRest(target: velocitySpring.target, threshold: config.visibilityThreshold * 10)
        if !releasePending && valueRest && pressRest && scaleRest && velocityRest {
            displayLink?.invalidate()
            displayLink = nil
            lastTimestamp = nil
        }
    }
}

// MARK: - Helpers

private struct SpringValue {
    var value: CGFloat
    var velocity: CGFloat = 0
    let response: CGFloat
    let dampingRatio: CGFloat
    var target: CGFloat = 0

    mutating func step(toward target: CGFloat, dt: CGFloat) {
        self.target = target
        let clampedResponse = max(0.0001, response)
        let omega0 = 2 * .pi / clampedResponse
        let x = value - target
        let f = -2 * dampingRatio * omega0 * velocity - omega0 * omega0 * x
        velocity += f * dt
        value += velocity * dt
    }

    func isAtRest(target: CGFloat, threshold: CGFloat) -> Bool {
        abs(value - target) < threshold && abs(velocity) < threshold
    }

    static func response(fromStiffness stiffness: CGFloat) -> CGFloat {
        let clamped = max(0.0001, stiffness)
        return 2 * .pi / sqrt(clamped)
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
