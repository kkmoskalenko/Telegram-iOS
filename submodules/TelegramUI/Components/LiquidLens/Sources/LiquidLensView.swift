import Foundation
import UIKit
import MetalKit
import Display
import ComponentFlow
import GlassBackgroundComponent
import LiquidLensSharedTypes

private final class RestingBackgroundView: UIVisualEffectView {
    var isDark: Bool?

    static func colorMatrix(isDark: Bool) -> [Float32] {
        if isDark {
            return [1.082, -0.113, -0.011, 0.0, 0.135, -0.034, 1.003, -0.011, 0.0, 0.135, -0.034, -0.113, 1.105, 0.0, 0.135, 0.0, 0.0, 0.0, 1.0, 0.0]
        } else {
            return [1.185, -0.05, -0.005, 0.0, -0.2, -0.015, 1.15, -0.005, 0.0, -0.2, -0.015, -0.05, 1.195, 0.0, -0.2, 0.0, 0.0, 0.0, 1.0, 0.0]
        }
    }

    init() {
        let effect = UIBlurEffect(style: .light)
        super.init(effect: effect)
        
        for subview in self.subviews {
            if subview.description.contains("VisualEffectSubview") {
                subview.isHidden = true
            }
        }
        
        self.clipsToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(isDark: Bool) {
        if self.isDark == isDark {
            return
        }
        self.isDark = isDark
        
        if let sublayer = self.layer.sublayers?[0], let _ = sublayer.filters {
            sublayer.backgroundColor = nil
            sublayer.isOpaque = false
            
            if let classValue = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol {
                let makeSelector = NSSelectorFromString("filterWithName:")
                let filter = classValue.perform(makeSelector, with: "colorMatrix").takeUnretainedValue() as? NSObject
                
                if let filter {
                    var matrix: [Float32] = RestingBackgroundView.colorMatrix(isDark: isDark)
                    filter.setValue(NSValue(bytes: &matrix, objCType: "{CAColorMatrix=ffffffffffffffffffff}"), forKey: "inputColorMatrix")
                    sublayer.filters = [filter]
                    sublayer.setValue(1.0, forKey: "scale")
                }
            }
        }
    }
}

public final class LiquidLensView: UIView {
    private struct Params: Equatable {
        var size: CGSize
        var selectionX: CGFloat
        var selectionWidth: CGFloat
        var isDark: Bool
        var isLifted: Bool

        init(size: CGSize, selectionX: CGFloat, selectionWidth: CGFloat, isDark: Bool, isLifted: Bool) {
            self.size = size
            self.selectionX = selectionX
            self.selectionWidth = selectionWidth
            self.isLifted = isLifted
            self.isDark = isDark
        }
    }

    private struct LensParams: Equatable {
        var baseFrame: CGRect
        var isLifted: Bool

        init(baseFrame: CGRect, isLifted: Bool) {
            self.baseFrame = baseFrame
            self.isLifted = isLifted
        }
    }

    private let containerView: UIView
    private let backgroundContainerContainer: UIView
    private let backgroundContainer: GlassBackgroundContainerView
    private let backgroundView: GlassBackgroundView
    private var lensView: UIView?
    private let liftedContainerView: UIView
    public let contentView: UIView
    private let restingBackgroundView: RestingBackgroundView
    
    private var legacySelectionView: GlassBackgroundView.ContentImageView?
    private var legacyContentMaskView: UIView?
    private var legacyContentMaskBlobView: UIImageView?
    private var legacyLiftedContentBlobMaskView: UIImageView?
    
    private var legacyLiquidGlassRenderer: LiquidGlassRenderer?
    private var legacyLiquidGlassView: MTKView?
    private var legacyLiquidGlassViewEdgeInsets: UIEdgeInsets = .zero
    private var legacyContentTexture: MTLTexture?
    private var legacySelectedContentTexture: MTLTexture?
    private var legacyDragAnimator: DragAnimator?

    public var selectedContentView: UIView {
        return self.liftedContainerView
    }

    private var params: Params?
    private var appliedLensParams: LensParams?
    private var isApplyingLensParams: Bool = false
    private var pendingLensParams: LensParams?

    private var liftedDisplayLink: SharedDisplayLinkDriver.Link?

    public var selectionX: CGFloat? {
        return self.params?.selectionX
    }

    public var selectionWidth: CGFloat? {
        return self.params?.selectionWidth
    }

    override public init(frame: CGRect) {
        self.containerView = UIView()
        
        self.backgroundContainerContainer = UIView()
        self.backgroundContainer = GlassBackgroundContainerView()
        
        self.backgroundView = GlassBackgroundView()
        
        self.contentView = UIView()
        self.liftedContainerView = UIView()

        self.restingBackgroundView = RestingBackgroundView()

        super.init(frame: frame)
        
        self.backgroundContainerContainer.addSubview(self.backgroundContainer)
        self.addSubview(self.backgroundContainerContainer)
        
        self.backgroundContainer.contentView.addSubview(self.backgroundView)
        self.backgroundView.contentView.addSubview(self.containerView)
        self.containerView.isUserInteractionEnabled = false
        
        if #available(iOS 26.0, *) {
            if let viewClass = NSClassFromString("_UILiquidLensView") as AnyObject as? NSObjectProtocol {
                let allocSelector = NSSelectorFromString("alloc")
                let initSelector = NSSelectorFromString("initWithRestingBackground:")
                let objcAlloc = viewClass.perform(allocSelector).takeUnretainedValue()
                let instance = objcAlloc.perform(initSelector, with: UIView()).takeUnretainedValue()
                self.lensView = instance as? UIView
            }
        }
        
        if let lensView = self.lensView {
            self.backgroundContainer.layer.zPosition = 1
            lensView.layer.zPosition = 10.0
            
            self.liftedContainerView.addSubview(self.restingBackgroundView)
            
            self.containerView.addSubview(self.liftedContainerView)
            self.containerView.addSubview(lensView)
            self.containerView.addSubview(self.contentView)
            
            lensView.perform(NSSelectorFromString("setLiftedContainerView:"), with: self.backgroundContainer.contentView)
            lensView.perform(NSSelectorFromString("setLiftedContentView:"), with: self.liftedContainerView)
            lensView.perform(NSSelectorFromString("setOverridePunchoutView:"), with: self.contentView)
            
            do {
                let selector = NSSelectorFromString("setLiftedContentMode:")
                if let method = lensView.method(for: selector) {
                    typealias ObjCMethod = @convention(c) (AnyObject, Selector, Int32) -> Void
                    let function = unsafeBitCast(method, to: ObjCMethod.self)
                    function(lensView, selector, 1)
                }
            }
            
            do {
                let selector = NSSelectorFromString("setStyle:")
                if let method = lensView.method(for: selector) {
                    typealias ObjCMethod = @convention(c) (AnyObject, Selector, Int32) -> Void
                    let function = unsafeBitCast(method, to: ObjCMethod.self)
                    function(lensView, selector, 1)
                }
            }
            
            do {
                let selector = NSSelectorFromString("setWarpsContentBelow:")
                if let method = lensView.method(for: selector) {
                    typealias ObjCMethod = @convention(c) (AnyObject, Selector, Bool) -> Void
                    let function = unsafeBitCast(method, to: ObjCMethod.self)
                    function(lensView, selector, true)
                }
            }
            
            lensView.setValue(UIColor(white: 0.0, alpha: 0.1), forKey: "restingBackgroundColor")
        } else {
            let legacySelectionView = GlassBackgroundView.ContentImageView()
            self.legacySelectionView = legacySelectionView
            self.backgroundView.contentView.insertSubview(legacySelectionView, at: 0)
            
            let legacyContentMaskView = UIView()
            legacyContentMaskView.backgroundColor = .white
            self.legacyContentMaskView = legacyContentMaskView
            self.contentView.mask = legacyContentMaskView
            
            if let filter = CALayer.luminanceToAlpha() {
                legacyContentMaskView.layer.filters = [filter]
            }
            
            let legacyContentMaskBlobView = UIImageView()
            self.legacyContentMaskBlobView = legacyContentMaskBlobView
            legacyContentMaskView.addSubview(legacyContentMaskBlobView)
            
            self.containerView.addSubview(self.contentView)
            
            let legacyLiftedContentBlobMaskView = UIImageView()
            self.legacyLiftedContentBlobMaskView = legacyLiftedContentBlobMaskView
            self.liftedContainerView.mask = legacyLiftedContentBlobMaskView
            
            self.containerView.addSubview(self.liftedContainerView)
            
            self.setupLiquidGlassView()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(size: CGSize, selectionX: CGFloat, selectionWidth: CGFloat, isDark: Bool, isLifted: Bool, transition: ComponentTransition) {
        let params = Params(size: size, selectionX: selectionX, selectionWidth: selectionWidth, isDark: isDark, isLifted: isLifted)
        if self.params == params {
            return
        }
        self.update(params: params, transition: transition)
    }

    private func update(transition: ComponentTransition) {
        guard let params = self.params else {
            return
        }
        self.update(params: params, transition: transition)
    }

    private func updateLens(params: LensParams, animated: Bool) {
        guard let lensView = self.lensView else {
            return
        }

        if self.isApplyingLensParams {
            self.pendingLensParams = params
            return
        }
        self.isApplyingLensParams = true
        let previousParams = self.appliedLensParams

        let transition: ComponentTransition = animated ? .easeInOut(duration: 0.3) : .immediate

        if previousParams?.isLifted != params.isLifted {
            let selector = NSSelectorFromString("setLifted:animated:alongsideAnimations:completion:")
            var shouldScheduleUpdate = false
            var didProcessUpdate = false
            self.pendingLensParams = params
            if let lensView = self.lensView, let method = lensView.method(for: selector) {
                typealias ObjCMethod = @convention(c) (AnyObject, Selector, Bool, Bool, @escaping () -> Void, AnyObject?) -> Void
                let function = unsafeBitCast(method, to: ObjCMethod.self)
                function(lensView, selector, params.isLifted, !transition.animation.isImmediate, { [weak self] in
                    guard let self else {
                        return
                    }
                    let liftedInset: CGFloat = params.isLifted ? 4.0 : -4.0
                    lensView.bounds = CGRect(origin: CGPoint(), size: CGSize(width: params.baseFrame.width + liftedInset * 2.0, height: params.baseFrame.height + liftedInset * 2.0))
                    didProcessUpdate = true
                    if shouldScheduleUpdate {
                        DispatchQueue.main.async { [weak self] in
                            guard let self, let pendingLensParams = self.pendingLensParams else {
                                return
                            }
                            self.isApplyingLensParams = false
                            self.pendingLensParams = nil
                            self.updateLens(params: pendingLensParams, animated: !transition.animation.isImmediate)
                        }
                    }
                }, nil)
            }
            if didProcessUpdate {
                transition.animateView {
                    lensView.center = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
                }
                self.pendingLensParams = nil
                self.isApplyingLensParams = false
            } else {
                shouldScheduleUpdate = true
            }
        } else {
            transition.animateView {
                let liftedInset: CGFloat = params.isLifted ? 4.0 : -4.0
                lensView.bounds = CGRect(origin: CGPoint(), size: CGSize(width: params.baseFrame.width + liftedInset * 2.0, height: params.baseFrame.height + liftedInset * 2.0))
                lensView.center = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
            }
            self.isApplyingLensParams = false
        }
    }

    private func updateLiftedLensPosition() {
        // Without this, the lens won't update its bouncing animations unless it's being moved
        if self.isApplyingLensParams {
            return
        }
        guard let lensView = self.lensView else {
            return
        }
        guard let params = self.appliedLensParams else {
            return
        }
        lensView.center = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
    }

    private func update(params: Params, transition: ComponentTransition) {
        let isFirstTime = self.params == nil
        let transition: ComponentTransition = isFirstTime ? .immediate : transition

        let previousParams = self.params
        self.params = params

        transition.setFrame(view: self.containerView, frame: CGRect(origin: CGPoint(), size: params.size))
        transition.setFrame(view: self.backgroundContainerContainer, frame: CGRect(origin: CGPoint(), size: params.size))

        transition.setPosition(view: self.backgroundContainer, position: CGPoint(x: params.size.width * 0.5, y: params.size.height * 0.5))
        transition.setBounds(view: self.backgroundContainer, bounds: CGRect(origin: CGPoint(), size: params.size))
        self.backgroundContainer.update(size: params.size, isDark: params.isDark, transition: transition)
        
        transition.setPosition(view: self.backgroundView, position: CGPoint(x: params.size.width * 0.5, y: params.size.height * 0.5))
        transition.setBounds(view: self.backgroundView, bounds: CGRect(origin: CGPoint(), size: params.size))
        self.backgroundView.update(size: params.size, cornerRadius: params.size.height * 0.5, isDark: params.isDark, tintColor: GlassBackgroundView.TintColor.init(kind: .panel, color: UIColor(white: params.isDark ? 0.0 : 1.0, alpha: 0.6)), isInteractive: true, transition: transition)
        
        transition.setFrame(view: self.contentView, frame: CGRect(origin: CGPoint(), size: params.size))
        transition.setFrame(view: self.liftedContainerView, frame: CGRect(origin: CGPoint(), size: params.size))

        let baseLensFrame = CGRect(origin: CGPoint(x: max(0.0, min(params.selectionX, params.size.width - params.selectionWidth)), y: 0.0), size: CGSize(width: params.selectionWidth, height: params.size.height))
        self.updateLens(params: LensParams(baseFrame: baseLensFrame, isLifted: params.isLifted), animated: !transition.animation.isImmediate)
        
        if let legacyContentMaskView = self.legacyContentMaskView {
            transition.setFrame(view: legacyContentMaskView, frame: CGRect(origin: CGPoint(), size: params.size))
        }
        if let legacyContentMaskBlobView = self.legacyContentMaskBlobView, let legacyLiftedContentBlobMaskView = self.legacyLiftedContentBlobMaskView, let legacySelectionView = self.legacySelectionView {
            let lensFrame = baseLensFrame.insetBy(dx: 4.0, dy: 4.0)
            let effectiveLensFrame = lensFrame.insetBy(dx: params.isLifted ? -2.0 : 0.0, dy: params.isLifted ? -2.0 : 0.0)
            
            if legacyContentMaskBlobView.image?.size.height != lensFrame.height {
                legacyContentMaskBlobView.image = generateStretchableFilledCircleImage(diameter: lensFrame.height, color: .black)
                legacyLiftedContentBlobMaskView.image = legacyContentMaskBlobView.image
                legacySelectionView.image = generateStretchableFilledCircleImage(diameter: lensFrame.height, color: .white)?.withRenderingMode(.alwaysTemplate)
            }
            transition.setFrame(view: legacyContentMaskBlobView, frame: effectiveLensFrame)
            transition.setFrame(view: legacyLiftedContentBlobMaskView, frame: effectiveLensFrame)
            
            legacySelectionView.tintColor = UIColor(white: params.isDark ? 1.0 : 0.0, alpha: params.isDark ? 0.1 : 0.075)
            transition.setFrame(view: legacySelectionView, frame: effectiveLensFrame)
        }
        if let legacyLiquidGlassView = self.legacyLiquidGlassView {
            let legacyLiquidGlassViewFrame = CGRect(origin: CGPoint(), size: params.size).inset(by: legacyLiquidGlassViewEdgeInsets)
            transition.setFrame(view: legacyLiquidGlassView, frame: legacyLiquidGlassViewFrame)
            
            // TODO: Animate lens transition
            legacyLiquidGlassView.isHidden = !params.isLifted
            self.contentView.isHidden = params.isLifted
            self.liftedContainerView.isHidden = params.isLifted
            self.legacySelectionView?.isHidden = params.isLifted
            
            if let legacyDragAnimator = self.legacyDragAnimator {
                if params.isLifted != previousParams?.isLifted {
                    if params.isLifted {
                        legacyDragAnimator.press()
                        transition.setScale(view: self.backgroundContainer, scale: 1.043)
                    } else {
                        legacyDragAnimator.release()
                        transition.setScale(view: self.backgroundContainer, scale: 1.0)
                    }
                }
                if params.selectionX != previousParams?.selectionX {
                    let selectionXNormalizer = params.size.width - params.selectionWidth
                    legacyDragAnimator.updateValue(params.selectionX / selectionXNormalizer)
                }
            } else {
                let lensFrame = baseLensFrame.insetBy(dx: 2.0, dy: 2.0)
                self.updateLiquidGlassRenderer(lensFrame: lensFrame)
            }
            
            if params.size != previousParams?.size || params.isDark != previousParams?.isDark {
                DispatchQueue.main.async { [weak self] in
                    self?.updateContentSnapshots(size: params.size)
                    if params.isLifted {
                        let lensFrame = baseLensFrame.insetBy(dx: 2.0, dy: 2.0)
                        self?.updateLiquidGlassRenderer(lensFrame: lensFrame)
                    }
                }
            }
        }

        transition.setFrame(view: self.restingBackgroundView, frame: CGRect(origin: CGPoint(), size: params.size))
        self.restingBackgroundView.update(isDark: params.isDark)
        transition.setAlpha(view: self.restingBackgroundView, alpha: params.isLifted ? 0.0 : 1.0)

        if params.isLifted {
            if self.liftedDisplayLink == nil {
                self.liftedDisplayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.updateLiftedLensPosition()
                })
            }
        } else if let liftedDisplayLink = self.liftedDisplayLink {
            self.liftedDisplayLink = nil
            liftedDisplayLink.invalidate()
        }
    }
}

// MARK: - Liquid Glass Effect with Metal

extension LiquidLensView {
    
    private func setupLiquidGlassView(pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = try? LiquidGlassRenderer(with: device, pixelFormat: pixelFormat)
        else {
            assertionFailure("Renderer creation failed")
            return
        }
        
        let view = MTKView(frame: .zero, device: device)
        view.delegate = renderer
        view.colorPixelFormat = pixelFormat
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.isOpaque = false
        view.layer.zPosition = 10.0
        
        self.legacyLiquidGlassRenderer = renderer
        self.legacyLiquidGlassView = view
        self.legacyLiquidGlassViewEdgeInsets = UIEdgeInsets(-20)
        
        self.backgroundContainer.layer.zPosition = 1.0
        self.containerView.addSubview(view)
        
        let dragAnimator = DragAnimator(config: DragAnimator.Config(
            initialValue: 0.0,
            valueRange: 0.0...1.0,
            initialScale: 1.0,
            // TODO: Verify the scale is correct
            pressedScale: 78.0 / 56.0
        ))
        dragAnimator.stateDidChange = { [weak self] state in
            guard let self, let params = self.params else { return }
            
            var scaleX = state.scaleX
            var scaleY = state.scaleY
            
            let velocity = state.velocity / 10.0
            scaleX /= 1.0 - (velocity * 0.75).clamped(to: -0.2...0.2)
            scaleY *= 1.0 - (velocity * 0.25).clamped(to: -0.2...0.2)
            
            let selectionXNormalizer = params.size.width - params.selectionWidth
            let lensFrame = CGRect(x: state.value * selectionXNormalizer,
                                   y: 0.0,
                                   width: params.selectionWidth,
                                   height: params.size.height)
            
            let dx = 4.0 + lensFrame.size.width  * (1 - scaleX) / 2
            let dy = 4.0 + lensFrame.size.height * (1 - scaleY) / 2
            
            self.updateLiquidGlassRenderer(lensFrame: lensFrame.insetBy(dx: dx, dy: dy))
        }
        self.legacyDragAnimator = dragAnimator
    }
    
    private func updateLiquidGlassRenderer(lensFrame: CGRect) {
        guard let view = self.legacyLiquidGlassView,
              let renderer = self.legacyLiquidGlassRenderer,
              let bgTexture = self.legacyContentTexture,
              let bgOverlayTexture = self.legacySelectedContentTexture
        else { return }
        
        let resolution: SIMD2<Float> = [Float(view.drawableSize.width), Float(view.drawableSize.height)]
        let dpr = Float(view.contentScaleFactor)
        
        let topLeftInset: SIMD2<Float> = dpr * [Float(-self.legacyLiquidGlassViewEdgeInsets.left),
                                                Float(-self.legacyLiquidGlassViewEdgeInsets.top)]
        let bottomRightInset: SIMD2<Float> = dpr * [Float(-self.legacyLiquidGlassViewEdgeInsets.right),
                                                    Float(-self.legacyLiquidGlassViewEdgeInsets.bottom)]
        let contentSize = resolution - topLeftInset - bottomRightInset
        
        let lensPosition: SIMD2<Float> = dpr * [Float(lensFrame.midX), Float(lensFrame.midY)] + topLeftInset
        let lensWidth = Float(lensFrame.width)
        let lensHeight = Float(lensFrame.height)
        
        let arguments = LiquidGlassArguments.default(
            resolution: resolution,
            dpr: dpr,
            mouse: lensPosition,
            mouseSpring: lensPosition,
            shadowExpand: 8.0,
            shadowFactor: 0.1,
            shadowPosition: [0.0, -8.0],
            contentOrigin: topLeftInset,
            contentSize: contentSize,
            shapeWidth: lensWidth,
            shapeHeight: lensHeight,
            shapeRadius: 0.5 * lensHeight,
            shapeRoundness: 2.0
        )
        
        renderer.update(view: view, backgroundTexture: bgTexture, backgroundOverlayTexture: bgOverlayTexture, arguments: arguments)
    }
    
    public func updateContentSnapshots(size: CGSize) {
        guard let renderer = self.legacyLiquidGlassRenderer else { return }
        
        // TODO: Render directly into MTLTexture memory
        let format = UIGraphicsImageRendererFormat()
        format.preferredRange = .standard
        
        let imageRenderer = UIGraphicsImageRenderer(size: size, format: format)
        
        func renderSubviews(of view: UIView) -> UIImage {
            imageRenderer.image { context in
                for subview in view.subviews {
                    context.cgContext.saveGState()
                    context.cgContext.translateBy(x: subview.frame.origin.x, y: subview.frame.origin.y)
                    subview.layer.render(in: context.cgContext)
                    context.cgContext.restoreGState()
                }
            }
        }
        
        let defaultImage = renderSubviews(of: self.contentView)
        let selectedImage = renderSubviews(of: self.liftedContainerView)
        
        do {
            self.legacyContentTexture = try renderer.loadTexture(from: defaultImage.cgImage!)
            self.legacySelectedContentTexture = try renderer.loadTexture(from: selectedImage.cgImage!)
        } catch {
            assertionFailure("Texture creation failed: \(error)")
        }
    }
}
