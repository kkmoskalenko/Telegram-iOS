import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import LegacyComponents
import AccountContext

// TODO: Replace with localized strings
private let titleText = "This call is end-to-end encrypted"
private let buttonText = "OK"

final class CallControllerKeyPreviewNode: ASDisplayNode {
    private let keyContainerNode: ASDisplayNode
    private let emojiNodes: [EmojiSlotNode]
    
    private let titleTextNode: ASTextNode
    private let infoTextNode: ASTextNode
    
    private let buttonNode: HighlightableButtonNode
    private let buttonSeparator: CALayer
    
    private let effectView: UIVisualEffectView
    private let backgroundContainerNode: ASDisplayNode
    
    private let accountContext: AccountContext
    var dismiss: (() -> Void)?
    
    var keyText: String = "" {
        didSet {
            guard self.keyText != oldValue else { return }
            EmojiSlotNode.updateNodes(self.emojiNodes, key: self.keyText, accountContext: self.accountContext)
        }
    }
    
    var infoText: String = "" {
        didSet {
            self.infoTextNode.attributedText = NSAttributedString(string: self.infoText, font: Font.regular(16.0), textColor: UIColor.white, paragraphAlignment: .center)
        }
    }
    
    init(accountContext: AccountContext) {
        self.keyContainerNode = ASDisplayNode()
        self.keyContainerNode.displaysAsynchronously = false
        self.emojiNodes = (0 ..< 4).map { _ in EmojiSlotNode() }
        
        self.titleTextNode = ASTextNode()
        self.titleTextNode.displaysAsynchronously = false
        self.titleTextNode.maximumNumberOfLines = 1
        
        self.infoTextNode = ASTextNode()
        self.infoTextNode.displaysAsynchronously = false
        self.infoTextNode.maximumNumberOfLines = 2
        
        self.buttonNode = HighlightableButtonNode()
        self.buttonSeparator = CALayer()
        
        self.accountContext = accountContext
        
        self.effectView = UIVisualEffectView()
        self.effectView.layer.masksToBounds = true
        self.buttonNode.layer.masksToBounds = true
        self.effectView.layer.cornerRadius = 20.0
        self.buttonNode.layer.cornerRadius = 20.0
        self.buttonNode.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        if #available(iOS 13.0, *) {
            self.effectView.layer.cornerCurve = .continuous
            self.buttonNode.layer.cornerCurve = .continuous
        }
        
        self.backgroundContainerNode = ASDisplayNode()
        self.backgroundContainerNode.displaysAsynchronously = false
        self.backgroundContainerNode.layer.anchorPoint = CGPoint(x: 1.0, y: 0.0)
        
        super.init()
        
        self.titleTextNode.attributedText = NSAttributedString(string: titleText, font: Font.semibold(16.0), textColor: UIColor.white, paragraphAlignment: .center)
        self.buttonNode.setAttributedTitle(NSAttributedString(string: buttonText, font: Font.regular(20.0), textColor: UIColor.white, paragraphAlignment: .center), for: .normal)
        self.buttonNode.highligthedChanged = { [weak buttonNode] highlighted in
            if highlighted {
                buttonNode?.backgroundColor = UIColor.white.withAlphaComponent(0.2)
            } else {
                UIView.animate(withDuration: 0.3, animations: {
                    buttonNode?.backgroundColor = nil
                })
            }
        }
        
        self.addSubnode(self.backgroundContainerNode)
        self.backgroundContainerNode.view.addSubview(self.effectView)
        self.backgroundContainerNode.addSubnode(self.titleTextNode)
        self.backgroundContainerNode.addSubnode(self.infoTextNode)
        self.backgroundContainerNode.addSubnode(self.buttonNode)
        self.buttonNode.layer.addSublayer(self.buttonSeparator)
        
        self.addSubnode(self.keyContainerNode)
        self.emojiNodes.forEach { self.keyContainerNode.addSubnode($0) }
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.buttonNode.addTarget(self, action: #selector(self.buttonTapped), forControlEvents: .touchUpInside)
    }
    
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        self.effectView.frame = CGRect(origin: .zero, size: size)
        self.backgroundContainerNode.frame = CGRect(origin: .zero, size: size)
        
        let keyContainerSize = CGSize(width: 210.0, height: 48.0)
        transition.updateFrame(node: self.keyContainerNode, frame: CGRect(origin: CGPoint(x: (size.width - keyContainerSize.width) / 2.0, y: 20.0), size: keyContainerSize))
        
        for (index, node) in self.emojiNodes.enumerated() {
            let offsetX = CGFloat(index) * (48.0 + 6.0)
            transition.updateFrame(node: node, frame: CGRect(x: offsetX, y: 0.0, width: 48.0, height: 48.0))
        }
        
        let titleTextSize = self.titleTextNode.measure(CGSize(width: size.width - 32.0, height: CGFloat.greatestFiniteMagnitude))
        transition.updateFrame(node: self.titleTextNode, frame: CGRect(origin: CGPoint(x: floor((size.width - titleTextSize.width) / 2.0), y: floor(self.keyContainerNode.frame.maxY + 10.0)), size: titleTextSize))
        
        let infoTextSize = self.infoTextNode.measure(CGSize(width: size.width - 32.0, height: CGFloat.greatestFiniteMagnitude))
        transition.updateFrame(node: self.infoTextNode, frame: CGRect(origin: CGPoint(x: floor((size.width - infoTextSize.width) / 2.0), y: floor(self.titleTextNode.frame.maxY + 10.0)), size: infoTextSize))
        
        let buttonFrame = CGRect(x: 0.0, y: size.height - 56.0, width: size.width, height: 56.0)
        transition.updateFrame(node: self.buttonNode, frame: buttonFrame)
        
        self.buttonSeparator.frame = CGRect(origin: .zero, size: CGSize(width: buttonFrame.width, height: UIScreenPixel))
    }
    
    func animateIn(from rect: CGRect, fromNode: ASDisplayNode, lightStyle: Bool) {
        self.keyContainerNode.layer.animatePosition(from: CGPoint(x: rect.midX, y: rect.midY), to: self.keyContainerNode.layer.position, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)
        
        if let transitionView = fromNode.view.snapshotView(afterScreenUpdates: false) {
            self.view.addSubview(transitionView)
            transitionView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            transitionView.layer.animatePosition(from: CGPoint(x: rect.midX, y: rect.midY), to: self.keyContainerNode.layer.position, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, completion: { [weak transitionView] _ in
                transitionView?.removeFromSuperview()
            })
            transitionView.layer.animateScale(from: 1.0, to: self.keyContainerNode.frame.size.width / rect.size.width, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
        }
        
        self.keyContainerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.15)
        self.keyContainerNode.layer.animateScale(from: rect.size.width / self.keyContainerNode.frame.size.width, to: 1.0, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)
        self.emojiNodes.forEach { $0.playOnce() }
        
        self.backgroundContainerNode.layer.animateScale(from: 0.1, to: 1.0, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)
        self.backgroundContainerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)
        
        UIView.animate(withDuration: 0.3, animations: {
            self.effectView.effect = UIBlurEffect(style: lightStyle ? .light : .dark)
            self.effectView.alpha = lightStyle ? 0.85 : 1.0
            self.buttonSeparator.backgroundColor = UIColor(white: lightStyle ? 0.0 : 1.0, alpha: lightStyle ? 0.4 : 0.5).cgColor
        })
    }
    
    func animateOut(to rect: CGRect, toNode: ASDisplayNode, completion: @escaping () -> Void) {
        self.keyContainerNode.layer.animatePosition(from: self.keyContainerNode.layer.position, to: CGPoint(x: rect.midX, y: rect.midY), duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, completion: { _ in
            completion()
        })
        self.keyContainerNode.layer.animateScale(from: 1.0, to: rect.size.width / self.keyContainerNode.frame.size.width, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
        self.emojiNodes.forEach { $0.stop() }
        
        self.backgroundContainerNode.layer.animateScale(from: 1.0, to: 0.1, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
        self.backgroundContainerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
        
        UIView.animate(withDuration: 0.2, animations: {
            self.effectView.effect = nil
        })
    }
    
    @objc private func buttonTapped() {
        self.dismiss?()
    }
}

