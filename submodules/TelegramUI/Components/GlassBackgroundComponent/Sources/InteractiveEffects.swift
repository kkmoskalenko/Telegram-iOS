import UIKit

public final class InteractiveEffectsHandle: NSObject, UIGestureRecognizerDelegate {
    private weak var view: UIView?
    private weak var highlightView: InteractiveHighlightView?
    private weak var gestureRecognizer: UILongPressGestureRecognizer?

    private var startLocation: CGPoint = .zero
    private var pressProgress: CGFloat = 0
    private var currentOffset: CGPoint = .zero

    init(
        view: UIView,
        highlightView: InteractiveHighlightView,
        gestureRecognizer: UILongPressGestureRecognizer
    ) {
        self.view = view
        self.highlightView = highlightView
        self.gestureRecognizer = gestureRecognizer
        super.init()

        gestureRecognizer.delegate = self
        gestureRecognizer.addTarget(self, action: #selector(handleGesture(_:)))
    }

    deinit {
        uninstall()
    }

    public func uninstall() {
        gestureRecognizer?.removeTarget(self, action: #selector(handleGesture(_:)))
        if let gestureRecognizer, let view {
            view.removeGestureRecognizer(gestureRecognizer)
        }
        highlightView?.removeFromSuperview()
    }

    // MARK: - Gesture handling

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === self.gestureRecognizer {
            return true
        }
        return false
    }

    @objc
    private func handleGesture(_ gesture: UILongPressGestureRecognizer) {
        guard let view else { return }
        let location = gesture.location(in: view)

        switch gesture.state {
        case .began:
            startLocation = location
            currentOffset = .zero
            pressProgress = 1
            highlightView?.touchPoint = location
            animateTo(press: 1, offset: .zero)
        case .changed:
            let offset = CGPoint(x: location.x - startLocation.x, y: location.y - startLocation.y)
            currentOffset = offset
            highlightView?.touchPoint = location
            applyTransform(press: pressProgress, offset: offset, animated: false)
        case .ended, .cancelled, .failed:
            currentOffset = .zero
            pressProgress = 0
            animateTo(press: 0, offset: .zero)
        default:
            break
        }
    }

    // MARK: - Animation and transforms

    private func animateTo(press: CGFloat, offset: CGPoint) {
        guard let view else { return }

        let targetTransform = transform(for: press, offset: offset, in: view.bounds.size)
        
        UIView.animate(
            withDuration: 0.5,
            delay: 0.0,
            usingSpringWithDamping: 0.5,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) { [weak self, weak view] in
            view?.transform = targetTransform
            self?.highlightView?.layer.opacity = Float(press)
        }
    }

    private func applyTransform(press: CGFloat, offset: CGPoint, animated: Bool) {
        guard let view else { return }
        let transform = transform(for: press, offset: offset, in: view.bounds.size)

        if animated {
            animateTo(press: press, offset: offset)
        } else {
            UIView.performWithoutAnimation {
                view.transform = transform
                highlightView?.layer.opacity = Float(press)
            }
        }
    }

    private func transform(for press: CGFloat, offset: CGPoint, in size: CGSize) -> CGAffineTransform {
        let width = size.width
        let height = size.height
        let minDim = min(width, height)
        let maxDim = max(width, height)

        let baseScaleDelta: CGFloat = (4.0 / max(height, 0.0001)) * press
        let scale = 1 + baseScaleDelta

        let maxOffset = minDim
        let initialDerivative: CGFloat = 0.05
        let translationX = maxOffset * tanh(initialDerivative * offset.x / maxOffset)
        let translationY = maxOffset * tanh(initialDerivative * offset.y / maxOffset)

        let maxDragScale: CGFloat = 4.0 / max(height, 0.0001)
        let angle = atan2(offset.y, offset.x)
        let stretchX =
            maxDragScale *
            abs(cos(angle) * offset.x / max(maxDim, 0.0001)) *
            min(width / max(height, 0.0001), 1)
        let stretchY =
            maxDragScale *
            abs(sin(angle) * offset.y / max(maxDim, 0.0001)) *
            min(height / max(width, 0.0001), 1)

        let scaleX = scale + stretchX
        let scaleY = scale + stretchY

        return CGAffineTransform(translationX: translationX, y: translationY)
            .scaledBy(x: scaleX, y: scaleY)
    }
}

// MARK: - UIView extension

public extension UIView {

    func installInteractiveEffects(cornerRadius: CGFloat? = nil) -> InteractiveEffectsHandle {
        let highlightView = InteractiveHighlightView()
        highlightView.frame = bounds
        highlightView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        highlightView.layer.opacity = 0
        highlightView.layer.cornerRadius = cornerRadius ?? layer.cornerRadius
        highlightView.layer.masksToBounds = true
        addSubview(highlightView)

        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0
        recognizer.cancelsTouchesInView = false
        recognizer.allowableMovement = .greatestFiniteMagnitude

        let handle = InteractiveEffectsHandle(
            view: self,
            highlightView: highlightView,
            gestureRecognizer: recognizer
        )
        addGestureRecognizer(recognizer)
        return handle
    }
}

// MARK: - Highlight view

final class InteractiveHighlightView: UIView {
    var touchPoint: CGPoint = .zero {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        contentScaleFactor = UIScreen.main.scale
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let progress = CGFloat(layer.opacity)
        let isDark = traitCollection.userInterfaceStyle == .dark
        guard progress > 0 else { return }

        let center = CGPoint(
            x: touchPoint.x.clamped(to: 0...rect.width),
            y: touchPoint.y.clamped(to: 0...rect.height)
        )
        let radius = min(rect.width, rect.height) * 1.5

        ctx.setBlendMode(.plusLighter)

        ctx.setFillColor(UIColor.white.withAlphaComponent(isDark ? 0.1 : 0.35).cgColor)
        ctx.fill(rect)

        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor.white.withAlphaComponent(isDark ? 0.08 : 0.25).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor
            ] as CFArray,
            locations: [0, 1]
        ) {
            ctx.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: radius,
                options: [.drawsAfterEndLocation]
            )
        }
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
