import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import LegacyComponents
import AnimatedCountLabelNode

private let nameFont = Font.regular(28.0)
private let statusFont = Font.with(size: 16.0, traits: .monospacedNumbers)

enum CallControllerStatusValue: Equatable {
    case text(string: String)
    case timer(timestamp: Double, reception: Int32)
    case ended
}

final class CallControllerStatusNode: ASDisplayNode {
    private let titleNode: ImmediateTextNode
    private let statusContainerNode: ASDisplayNode
    private let statusNode: ImmediateAnimatedCountLabelNode
    private let receptionNode: CallControllerReceptionNode
    private let indicatorNode: CallControllerActivityIndicatorNode
    
    private let titleActivateAreaNode: AccessibilityAreaNode
    private let statusActivateAreaNode: AccessibilityAreaNode
    
    var title: String = "" {
        didSet {
            guard self.title != oldValue else { return }
            
            if let validLayoutWidth = self.validLayoutWidth {
                UIView.transition(with: self.titleNode.view, duration: 0.2, options: .transitionCrossDissolve) { [weak self] in
                    let _ = self?.updateLayout(constrainedWidth: validLayoutWidth)
                }
            }
        }
    }
    
    var status: CallControllerStatusValue = .text(string: "") {
        didSet {
            if self.status != oldValue {
                self.statusTimer?.invalidate()
                
                let withoutAnimation: Bool
                if case .timer = oldValue, case .ended = self.status {
                    withoutAnimation = true
                } else {
                    withoutAnimation = false
                }
                
                if let snapshotView = self.statusContainerNode.view.snapshotView(afterScreenUpdates: false), !withoutAnimation {
                    snapshotView.frame = self.statusContainerNode.frame
                    self.view.insertSubview(snapshotView, belowSubview: self.statusContainerNode.view)
                    
                    snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                        snapshotView?.removeFromSuperview()
                    })
                    snapshotView.layer.animateScale(from: 1.0, to: 0.3, duration: 0.3, removeOnCompletion: false)
                    snapshotView.layer.animatePosition(from: CGPoint(), to: CGPoint(x: 0.0, y: snapshotView.frame.height / 2.0), duration: 0.3, delay: 0.0, removeOnCompletion: false, additive: true)
                    
                    self.statusContainerNode.layer.animateScale(from: 0.3, to: 1.0, duration: 0.3)
                    self.statusContainerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
                    self.statusContainerNode.layer.animatePosition(from: CGPoint(x: 0.0, y: -snapshotView.frame.height / 2.0), to: CGPoint(), duration: 0.3, delay: 0.0, additive: true)
                }
                                
                if case .timer(let timestamp, let reception) = self.status {
                    self.lastKnownTimestamp = timestamp
                    self.receptionNode.reception = reception
                    
                    self.statusTimer = SwiftSignalKit.Timer(timeout: 0.5, repeat: true, completion: { [weak self] in
                        if let strongSelf = self, let validLayoutWidth = strongSelf.validLayoutWidth {
                            let _ = strongSelf.updateLayout(constrainedWidth: validLayoutWidth)
                        }
                    }, queue: Queue.mainQueue())
                    self.statusTimer?.start()
                } else {
                    if let validLayoutWidth = self.validLayoutWidth {
                        let _ = self.updateLayout(constrainedWidth: validLayoutWidth)
                    }
                }
                
                if self.status == .ended {
                    self.receptionNode.reception = .min
                }
            }
        }
    }
    
    private var lastKnownTimestamp: Double?
    private var statusTimer: SwiftSignalKit.Timer?
    private var validLayoutWidth: CGFloat?
    
    override init() {
        self.titleNode = ImmediateTextNode()
        self.titleNode.maximumNumberOfLines = 1
        
        self.statusContainerNode = ASDisplayNode()
        self.statusNode = ImmediateAnimatedCountLabelNode()
        self.statusNode.alwaysOneDirection = true
       
        self.receptionNode = CallControllerReceptionNode()
        self.receptionNode.isHidden = true
        
        self.indicatorNode = CallControllerActivityIndicatorNode(color: .white)
        self.indicatorNode.isHidden = true
        
        self.titleActivateAreaNode = AccessibilityAreaNode()
        self.titleActivateAreaNode.accessibilityTraits = .staticText
        
        self.statusActivateAreaNode = AccessibilityAreaNode()
        self.statusActivateAreaNode.accessibilityTraits = [.staticText, .updatesFrequently]
        
        super.init()
        
        self.isUserInteractionEnabled = false
        
        self.addSubnode(self.titleNode)
        self.addSubnode(self.statusContainerNode)
        self.statusContainerNode.addSubnode(self.statusNode)
        self.statusContainerNode.addSubnode(self.receptionNode)
        self.statusContainerNode.addSubnode(self.indicatorNode)
        
        self.addSubnode(self.titleActivateAreaNode)
        self.addSubnode(self.statusActivateAreaNode)
    }
    
    deinit {
        self.statusTimer?.invalidate()
    }
    
    func setVisible(_ visible: Bool, transition: ContainedViewLayoutTransition) {
        let alpha: CGFloat = visible ? 1.0 : 0.0
        transition.updateAlpha(node: self.titleNode, alpha: alpha)
        transition.updateAlpha(node: self.statusContainerNode, alpha: alpha)
    }
    
    func updateLayout(constrainedWidth: CGFloat) -> CGFloat {
        self.validLayoutWidth = constrainedWidth
        
        let statusString: String
        let statusSegments: [AnimatedCountLabelNode.Segment]
        
        switch self.status {
        case var .text(string):
            // TODO: Remove ellipsis from localization strings
            while string.last == "." {
                string.removeLast()
            }
            statusString = string
            statusSegments = [.text(0, NSAttributedString(string: string, font: statusFont, textColor: .white))]
        case let .timer(referenceTime, _):
            (statusString, statusSegments) = formatString(referenceTime: referenceTime)
        case .ended:
            (statusString, statusSegments) = formatString(referenceTime: self.lastKnownTimestamp)
        }
        
        self.titleNode.attributedText = NSAttributedString(string: self.title, font: nameFont, textColor: .white)
        self.statusNode.segments = statusSegments
        
        self.titleActivateAreaNode.accessibilityLabel = self.title
        self.statusActivateAreaNode.accessibilityLabel = statusString
        
        let constrainedSize = CGSize(width: constrainedWidth - 20.0, height: .greatestFiniteMagnitude)
        
        let titleSize = self.titleNode.updateLayout(constrainedSize)
        self.titleNode.frame = CGRect(origin: CGPoint(x: (constrainedWidth - titleSize.width) / 2.0, y: 0.0), size: titleSize)
        
        let statusSize = self.statusNode.updateLayout(size: constrainedSize, animated: true)
        let statusContainerSize = CGSize(width: 20.0 + 6.0 + statusSize.width, height: statusSize.height)
        
        self.statusContainerNode.frame = CGRect(origin: CGPoint(x: (constrainedWidth - statusContainerSize.width) / 2.0, y: titleSize.height + 4.0), size: statusContainerSize)
        
        switch self.status {
        case .text:
            self.receptionNode.isHidden = true
            self.indicatorNode.isHidden = false
            
            self.statusNode.frame = CGRect(origin: .zero, size: statusSize)
            self.indicatorNode.frame = CGRect(origin: CGPoint(x: self.statusNode.frame.maxX + 5.0, y: 1.0), size: activityIndicatorSize)
        case .timer, .ended:
            self.receptionNode.isHidden = false
            self.indicatorNode.isHidden = true
            
            self.statusNode.frame = CGRect(origin: CGPoint(x: receptionNodeSize.width + 6.0, y: 0.0), size: statusSize)
            self.receptionNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -5.0), size: receptionNodeSize)
        }
        
        self.titleActivateAreaNode.frame = self.titleNode.frame
        self.statusActivateAreaNode.frame = self.statusContainerNode.frame
        
        return titleSize.height + 4.0 + statusSize.height
    }
    
    private func formatString(referenceTime: Double?) -> (string: String, segments: [AnimatedCountLabelNode.Segment]) {
        let duration = referenceTime.map { Int(CFAbsoluteTimeGetCurrent() - $0) } ?? 0
        let formattedString: String
        var segments = [AnimatedCountLabelNode.Segment]()
        
        if duration > 60 * 60 {
            formattedString = String(format: "%02d:%02d:%02d", arguments: [duration / 3600, (duration / 60) % 60, duration % 60])
        } else {
            formattedString = String(format: "%02d:%02d", arguments: [(duration / 60) % 60, duration % 60])
        }
        
        var textIndex = 0
        for char in formattedString {
            let attributedString = NSAttributedString(string: String(char), font: statusFont, textColor: .white)
            if let value = char.wholeNumberValue {
                segments.append(.number(value, attributedString))
            } else {
                segments.append(.text(textIndex, attributedString))
                textIndex += 1
            }
        }
        
        return (formattedString, segments)
    }
}

// MARK: - Reception Node

private let receptionNodeSize = CGSize(width: 20.0, height: 20.0)

private final class CallControllerReceptionNodeParameters: NSObject {
    let reception: Int32
    
    init(reception: Int32) {
        self.reception = reception
    }
}

private final class CallControllerReceptionNode : ASDisplayNode {
    var reception: Int32 = 0 {
        didSet {
            guard self.reception != oldValue else { return }
            UIView.transition(with: self.view, duration: 0.2, options: .transitionCrossDissolve) { [weak self] in
                self?.setNeedsDisplay()
            }
        }
    }
    
    override init() {
        super.init()
        self.isOpaque = false
    }
    
    override func drawParameters(forAsyncLayer layer: _ASDisplayLayer) -> NSObjectProtocol? {
        return CallControllerReceptionNodeParameters(reception: self.reception)
    }
    
    @objc override class func draw(_ bounds: CGRect, withParameters parameters: Any?, isCancelled: () -> Bool, isRasterizing: Bool) {
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.white.cgColor)
        
        if let parameters = parameters as? CallControllerReceptionNodeParameters, parameters.reception != .min {
            let width: CGFloat = 3.0
            let spacing: CGFloat = 2.0
            
            for i in 0 ..< 4 {
                let height = 3.0 * CGFloat(i + 1)
                let rect = CGRect(x: bounds.minX + 1.0 + CGFloat(i) * (width + spacing), y: receptionNodeSize.height - height, width: width, height: height)
                
                if i >= parameters.reception {
                    context.setAlpha(0.3)
                }
                
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 1.0)
                context.addPath(path.cgPath)
                context.fillPath()
            }
        } else {
            let callEndedImage = UIImage(bundleImageName: "Call/CallEndedIcon")
            callEndedImage?.draw(at: CGPoint(x: 0.0, y: 4.0))
        }
    }
}

// MARK: - Activity Indicator

private let minDiameter: CGFloat = 2.0
private let maxDiameter: CGFloat = 4.0
private let activityIndicatorSize = CGSize(width: 24.0, height: 16.0)

private func interpolate(from: CGFloat, to: CGFloat, value: CGFloat) -> CGFloat {
    return (1.0 - value) * from + value * to
}

private func radiusFunction(value: CGFloat, timeOffset: CGFloat) -> CGFloat {
    var clampedValue = value + timeOffset
    if clampedValue > 1.0 {
        clampedValue = clampedValue - floor(clampedValue)
    }
    if clampedValue < 0.4 {
        return interpolate(from: minDiameter, to: maxDiameter, value: clampedValue / 0.4)
    } else if clampedValue < 0.8 {
        return interpolate(from: maxDiameter, to: minDiameter, value: (clampedValue - 0.4) / 0.4)
    }
    return minDiameter
}

private final class CallControllerActivityIndicatorNodeParameters: NSObject {
    let color: UIColor
    let progress: CGFloat
    
    init(color: UIColor, progress: CGFloat) {
        self.color = color
        self.progress = progress
    }
}

private final class CallControllerActivityIndicatorNode: ASDisplayNode {
    
    var duration: CFTimeInterval {
        return 1.0
    }
    
    var timingFunction: CAMediaTimingFunction {
        return CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
    }
    
    var color: UIColor? {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    var progress: CGFloat = 0.0 {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    init(color: UIColor) {
        self.color = color
        
        super.init()
        
        self.isLayerBacked = true
        self.displaysAsynchronously = true
        self.isOpaque = false
    }
    
    deinit {
        self.stopAnimation()
    }
    
    private func startAnimation() {
        self.stopAnimation()
        
        let animation = POPBasicAnimation()
        animation.property = POPAnimatableProperty.property(withName: "progress", initializer: { property in
            property?.readBlock = { node, values in
                values?.pointee = (node as! CallControllerActivityIndicatorNode).progress
            }
            property?.writeBlock = { node, values in
                (node as! CallControllerActivityIndicatorNode).progress = values!.pointee
            }
            property?.threshold = 0.01
        }) as? POPAnimatableProperty
        animation.fromValue = 0.0 as NSNumber
        animation.toValue = 1.0 as NSNumber
        animation.timingFunction = self.timingFunction
        animation.duration = self.duration
        animation.repeatForever = true
        
        self.pop_add(animation, forKey: "animation")
    }
    
    private func stopAnimation() {
        self.pop_removeAnimation(forKey: "animation")
    }
    
    override public func didEnterHierarchy() {
        super.didEnterHierarchy()
        self.startAnimation()
    }
    
    override public func didExitHierarchy() {
        super.didExitHierarchy()
        self.stopAnimation()
    }
    
    override func drawParameters(forAsyncLayer layer: _ASDisplayLayer) -> NSObjectProtocol? {
        if let color = self.color {
            return CallControllerActivityIndicatorNodeParameters(color: color, progress: self.progress)
        } else {
            return nil
        }
    }
    
    @objc override class func draw(_ bounds: CGRect, withParameters parameters: Any?, isCancelled: () -> Bool, isRasterizing: Bool) {
        let context = UIGraphicsGetCurrentContext()!
        
        if !isRasterizing {
            context.setBlendMode(.copy)
            context.setFillColor(UIColor.clear.cgColor)
            context.fill(bounds)
        }
        
        guard let parameters = parameters as? CallControllerActivityIndicatorNodeParameters else {
            return
        }
        
        let leftPadding: CGFloat = 6.0
        let topPadding: CGFloat = 9.0
        let distance: CGFloat = 11.0 / 2.0

        let minAlpha: CGFloat = 1.0
        let deltaAlpha: CGFloat = 1.0 - minAlpha

        var radius = radiusFunction(value: parameters.progress, timeOffset: 0.4)
        radius = (max(minDiameter, radius) - minDiameter) / (maxDiameter - minDiameter)
        radius = radius * 1.5

        let initialAlpha = parameters.color.alpha
        var dotsColor = parameters.color.withAlphaComponent((radius * deltaAlpha + minAlpha) * initialAlpha)
        context.setFillColor(dotsColor.cgColor)
        
        context.fillEllipse(in: CGRect(x: leftPadding - minDiameter / 2.0 - radius / 2.0, y: topPadding - minDiameter / 2.0 - radius / 2.0, width: minDiameter + radius, height: minDiameter + radius))
        
        radius = radiusFunction(value: parameters.progress, timeOffset: 0.2)
        radius = (max(minDiameter, radius) - minDiameter) / (maxDiameter - minDiameter)
        radius = radius * 1.5
        
        dotsColor = parameters.color.withAlphaComponent((radius * deltaAlpha + minAlpha) * initialAlpha)
        context.setFillColor(dotsColor.cgColor)
        
        context.fillEllipse(in: CGRect(x: leftPadding + distance - minDiameter / 2.0 - radius / 2.0, y: topPadding - minDiameter / 2.0 - radius / 2.0, width: minDiameter + radius, height: minDiameter + radius))
        
        radius = radiusFunction(value: parameters.progress, timeOffset: 0.0)
        radius = (max(minDiameter, radius) - minDiameter) / (maxDiameter - minDiameter)
        radius = radius * 1.5
        
        dotsColor = parameters.color.withAlphaComponent((radius * deltaAlpha + minAlpha) * initialAlpha)
        context.setFillColor(dotsColor.cgColor)
        
        context.fillEllipse(in: CGRect(x: leftPadding + distance * 2.0 - minDiameter / 2.0 - radius / 2.0, y: topPadding - minDiameter / 2.0 - radius / 2.0, width: minDiameter + radius, height: minDiameter + radius))
    }
}
