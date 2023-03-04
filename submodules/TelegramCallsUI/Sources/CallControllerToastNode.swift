import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData

private enum ToastDescription: Equatable {
    enum Key: Hashable {
        case camera
        case microphone
        case mute
        case battery
        case network
    }
    
    case camera
    case microphone
    case mute
    case battery
    case network
    
    var key: Key {
        switch self {
        case .camera:
            return .camera
        case .microphone:
            return .microphone
        case .mute:
            return .mute
        case .battery:
            return .battery
        case .network:
            return .network
        }
    }
}

struct CallControllerToastContent: OptionSet {
    public var rawValue: Int32
    
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
    
    public static let camera = CallControllerToastContent(rawValue: 1 << 0)
    public static let microphone = CallControllerToastContent(rawValue: 1 << 1)
    public static let mute = CallControllerToastContent(rawValue: 1 << 2)
    public static let battery = CallControllerToastContent(rawValue: 1 << 3)
}

final class CallControllerToastContainerNode: ASDisplayNode {
    private var toastNodes: [ToastDescription.Key: CallControllerToastItemNode] = [:]
    private var visibleToastNodes: [CallControllerToastItemNode] = []
    
    private let strings: PresentationStrings
    
    private var validLayout: (CGFloat, CGFloat)?
    
    private var content: CallControllerToastContent?
    private var appliedContent: CallControllerToastContent?
    var title: String = ""
    
    init(strings: PresentationStrings) {
        self.strings = strings
        
        super.init()
    }
    
    private func updateToastsLayout(strings: PresentationStrings, content: CallControllerToastContent, lightStyle: Bool, width: CGFloat, bottomInset: CGFloat, animated: Bool) -> CGFloat {
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.3, curve: .spring)
        } else {
            transition = .immediate
        }
        
        self.appliedContent = content
        
        let spacing: CGFloat = 12.0
    
        var height: CGFloat = 0.0
        var toasts: [ToastDescription] = []
        
        if content.contains(.camera) {
            toasts.append(.camera)
        }
        if content.contains(.microphone) {
            toasts.append(.microphone)
        }
        if content.contains(.mute) {
            toasts.append(.mute)
        }
        if content.contains(.battery) {
            toasts.append(.battery)
        }
        
        var transitions: [ToastDescription.Key: (ContainedViewLayoutTransition, CGFloat, Bool)] = [:]
        var validKeys: [ToastDescription.Key] = []
        for toast in toasts {
            validKeys.append(toast.key)
            var toastTransition = transition
            var animateIn = false
            let toastNode: CallControllerToastItemNode
            if let current = self.toastNodes[toast.key] {
                toastNode = current
            } else {
                toastNode = CallControllerToastItemNode()
                self.toastNodes[toast.key] = toastNode
                self.addSubnode(toastNode)
                self.visibleToastNodes.append(toastNode)
                toastTransition = .immediate
                animateIn = transition.isAnimated
            }
            let toastContent: CallControllerToastItemNode.Content
            switch toast {
                case .camera:
                    toastContent = CallControllerToastItemNode.Content(
                        key: .camera,
                        text: strings.Call_CameraOff(self.title).string
                    )
                case .microphone:
                    toastContent = CallControllerToastItemNode.Content(
                        key: .microphone,
                        text: strings.Call_MicrophoneOff(self.title).string
                    )
                case .mute:
                    toastContent = CallControllerToastItemNode.Content(
                        key: .mute,
                        // TODO: Update the localized string
                        text: strings.Call_YourMicrophoneOff
                            .replacingOccurrences(of: " is off", with: " is turned off")
                    )
                case .battery:
                    toastContent = CallControllerToastItemNode.Content(
                        key: .battery,
                        text: strings.Call_BatteryLow(self.title).string
                    )
                case .network:
                    continue
            }
            let toastHeight = toastNode.update(width: width, content: toastContent, lightStyle: lightStyle, transition: toastTransition)
            transitions[toast.key] = (toastTransition, toastHeight, animateIn)
        }
        
        var removedKeys: [ToastDescription.Key] = []
        for (key, toastNode) in self.toastNodes {
            if !validKeys.contains(key) {
                removedKeys.append(key)
                self.visibleToastNodes.removeAll { $0 === toastNode }
                if animated {
                    toastNode.animateOut() { [weak toastNode] in
                        toastNode?.removeFromSupernode()
                    }
                } else {
                    toastNode.removeFromSupernode()
                }
            }
        }
        for key in removedKeys {
            self.toastNodes.removeValue(forKey: key)
        }
        
        for toastNode in self.visibleToastNodes {
            if let content = toastNode.currentContent, let (transition, toastHeight, animateIn) = transitions[content.key] {
                transition.updateFrame(node: toastNode, frame: CGRect(x: 0.0, y: height, width: width, height: toastHeight))
                height += toastHeight + spacing
                
                if animateIn {
                    toastNode.animateIn()
                }
            }
        }
        if height > 0.0 {
            height -= spacing
        }
        
        return height
    }
    
    func updateLayout(strings: PresentationStrings, content: CallControllerToastContent?, lightStyle: Bool, constrainedWidth: CGFloat, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGFloat {
        self.validLayout = (constrainedWidth, bottomInset)
        
        self.content = content
        
        if let content = self.content {
            return self.updateToastsLayout(strings: strings, content: content, lightStyle: lightStyle, width: constrainedWidth, bottomInset: bottomInset, animated: transition.isAnimated)
        } else {
            return 0.0
        }
    }
}

final class CallControllerToastItemNode: ASDisplayNode {
    struct Content: Equatable {
        fileprivate var key: ToastDescription.Key
        fileprivate var text: String
        
        // TODO: Add a localized string
        static let weakNetwork = Content(key: .network, text: "Weak network signal")
    }
    
    let clipNode: ASDisplayNode
    let effectView: UIVisualEffectView
    let textNode: ImmediateTextNode
    
    private(set) var currentContent: Content?
    private(set) var currentWidth: CGFloat?
    private(set) var currentHeight: CGFloat?
    private(set) var hasLightStyle: Bool = true
    
    override init() {
        self.clipNode = ASDisplayNode()
        self.clipNode.clipsToBounds = true
        self.clipNode.layer.cornerRadius = 15.0
        
        self.effectView = UIVisualEffectView()
        self.effectView.effect = UIBlurEffect(style: .light)
        self.effectView.alpha = 0.85
        self.effectView.isUserInteractionEnabled = false
        
        self.textNode = ImmediateTextNode()
        self.textNode.maximumNumberOfLines = 2
        self.textNode.displaysAsynchronously = false
        self.textNode.isUserInteractionEnabled = false
        
        super.init()
        
        self.addSubnode(self.clipNode)
        self.clipNode.view.addSubview(self.effectView)
        self.clipNode.addSubnode(self.textNode)
    }
    
    override func didLoad() {
        super.didLoad()
        
        if #available(iOS 13.0, *) {
            self.clipNode.layer.cornerCurve = .continuous
        }
    }
    
    func update(width: CGFloat, content: Content, lightStyle: Bool, transition: ContainedViewLayoutTransition) -> CGFloat {
        let inset: CGFloat = 30.0
        let font = Font.regular(16.0)
        let textInsets = UIEdgeInsets(top: 5.0, left: 12.0, bottom: 6.0, right: 12.0)
                
        if self.currentContent != content || self.currentWidth != width {
            self.currentContent = content
            self.currentWidth = width
                  
            self.textNode.attributedText = NSAttributedString(string: content.text, font: font, textColor: .white)
            let textSize = self.textNode.updateLayout(CGSize(width: width - inset * 2.0, height: 100.0))
            
            let backgroundSize = CGSize(width: textSize.width + textInsets.left + textInsets.right, height: max(30.0, textSize.height + textInsets.top + textInsets.bottom))
            let backgroundFrame = CGRect(origin: CGPoint(x: floor((width - backgroundSize.width) / 2.0), y: 0.0), size: backgroundSize)
            
            transition.updateFrame(node: self.clipNode, frame: backgroundFrame)
            transition.updateFrame(view: self.effectView, frame: CGRect(origin: CGPoint(), size: backgroundFrame.size))
            
            self.textNode.frame = CGRect(origin: CGPoint(x: textInsets.left, y: textInsets.top), size: textSize)
            self.currentHeight = backgroundSize.height
        }
        
        if self.hasLightStyle != lightStyle {
            self.hasLightStyle = lightStyle
            
            let updateEffect = { [weak self] in self?.effectView.effect = UIBlurEffect(style: lightStyle ? .light : .dark) }
            let updateAlpha = { [weak self] in self?.effectView.alpha = lightStyle ? 0.85 : 1.0 }
            
            switch transition {
            case .immediate:
                updateEffect()
                updateAlpha()
            case .animated(let duration, _):
                if let snapshotView = self.effectView.snapshotView(afterScreenUpdates: false) {
                    self.effectView.superview?.insertSubview(snapshotView, belowSubview: self.effectView)
                    snapshotView.frame = self.effectView.frame
                    
                    self.effectView.alpha = 0.0
                    updateEffect()
                    
                    UIView.animate(withDuration: duration, delay: 0.0, options: .curveEaseInOut, animations: { [weak snapshotView] in
                        snapshotView?.alpha = 0.0
                        updateAlpha()
                    }, completion: { [weak snapshotView] _ in
                        snapshotView?.removeFromSuperview()
                    })
                } else {
                    updateEffect()
                    updateAlpha()
                }
            }
        }
        
        return self.currentHeight ?? 30.0
    }
    
    func animateIn() {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        self.layer.animateSpring(from: 0.01 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.3, damping: 105.0)
    }
    
    func animateOut(completion: @escaping () -> Void) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { _ in completion() })
        self.layer.animateSpring(from: 1.0 as NSNumber, to: 0.1 as NSNumber, keyPath: "transform.scale", duration: 0.3, damping: 105.0, removeOnCompletion: false)
    }
}
