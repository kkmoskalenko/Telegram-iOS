import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import LegacyComponents

// TODO: Replace with localized strings
private let titleText = "This call is end-to-end encrypted"
private let buttonText = "OK"

final class CallControllerKeyPreviewNode: ASDisplayNode {
    private let keyTextNode: ASTextNode
    private let titleTextNode: ASTextNode
    private let infoTextNode: ASTextNode
    
    private let buttonNode: HighlightableButtonNode
    private let buttonSeparator: CALayer
    
    private let effectView: UIVisualEffectView
    
    private let dismiss: () -> Void
    
    init(keyText: String, infoText: String, dismiss: @escaping () -> Void) {
        self.keyTextNode = ASTextNode()
        self.keyTextNode.displaysAsynchronously = false
        self.titleTextNode = ASTextNode()
        self.titleTextNode.displaysAsynchronously = false
        self.titleTextNode.maximumNumberOfLines = 1
        self.infoTextNode = ASTextNode()
        self.infoTextNode.displaysAsynchronously = false
        self.infoTextNode.maximumNumberOfLines = 2
        self.buttonNode = HighlightableButtonNode()
        self.buttonSeparator = CALayer()
        self.dismiss = dismiss
        
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
        
        super.init()
        
        self.keyTextNode.attributedText = NSAttributedString(string: keyText, attributes: [NSAttributedString.Key.font: Font.regular(40.0), NSAttributedString.Key.kern: 7.586 as NSNumber])
        self.titleTextNode.attributedText = NSAttributedString(string: titleText, font: Font.semibold(16.0), textColor: UIColor.white, paragraphAlignment: .center)
        self.infoTextNode.attributedText = NSAttributedString(string: infoText, font: Font.regular(16.0), textColor: UIColor.white, paragraphAlignment: .center)
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
        
        self.view.addSubview(self.effectView)
        self.addSubnode(self.keyTextNode)
        self.addSubnode(self.titleTextNode)
        self.addSubnode(self.infoTextNode)
        self.addSubnode(self.buttonNode)
        self.buttonNode.layer.addSublayer(self.buttonSeparator)
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.buttonNode.addTarget(self, action: #selector(self.buttonTapped), forControlEvents: .touchUpInside)
    }
    
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        self.effectView.frame = CGRect(origin: CGPoint(), size: size)
        
        let keyTextSize = self.keyTextNode.measure(CGSize(width: 300.0, height: 300.0))
        transition.updateFrame(node: self.keyTextNode, frame: CGRect(origin: CGPoint(x: floor((size.width - keyTextSize.width) / 2) + 6.0, y: 20.0), size: keyTextSize))
        
        let titleTextSize = self.titleTextNode.measure(CGSize(width: size.width - 32.0, height: CGFloat.greatestFiniteMagnitude))
        transition.updateFrame(node: self.titleTextNode, frame: CGRect(origin: CGPoint(x: floor((size.width - titleTextSize.width) / 2.0), y: floor(self.keyTextNode.frame.maxY + 10.0)), size: titleTextSize))
        
        let infoTextSize = self.infoTextNode.measure(CGSize(width: size.width - 32.0, height: CGFloat.greatestFiniteMagnitude))
        transition.updateFrame(node: self.infoTextNode, frame: CGRect(origin: CGPoint(x: floor((size.width - infoTextSize.width) / 2.0), y: floor(self.titleTextNode.frame.maxY + 10.0)), size: infoTextSize))
        
        let buttonFrame = CGRect(x: 0.0, y: size.height - 56.0, width: size.width, height: 56.0)
        transition.updateFrame(node: self.buttonNode, frame: buttonFrame)
        
        self.buttonSeparator.frame = CGRect(origin: .zero, size: CGSize(width: buttonFrame.width, height: UIScreenPixel))
    }
    
    func animateIn(from rect: CGRect, fromNode: ASDisplayNode, lightStyle: Bool) {
        self.keyTextNode.layer.animatePosition(from: CGPoint(x: rect.midX, y: rect.midY), to: self.keyTextNode.layer.position, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)
        if let transitionView = fromNode.view.snapshotView(afterScreenUpdates: false) {
            self.view.addSubview(transitionView)
            transitionView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            transitionView.layer.animatePosition(from: CGPoint(x: rect.midX, y: rect.midY), to: self.keyTextNode.layer.position, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, completion: { [weak transitionView] _ in
                transitionView?.removeFromSuperview()
            })
            transitionView.layer.animateScale(from: 1.0, to: self.keyTextNode.frame.size.width / rect.size.width, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
        }
        self.keyTextNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.15)
        
        self.keyTextNode.layer.animateScale(from: rect.size.width / self.keyTextNode.frame.size.width, to: 1.0, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)
        
        self.titleTextNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
        self.infoTextNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
        self.buttonNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
        self.buttonSeparator.backgroundColor = UIColor(white: lightStyle ? 0.0 : 1.0, alpha: lightStyle ? 0.4 : 0.5).cgColor
        
        UIView.animate(withDuration: 0.3, animations: {
            self.effectView.effect = UIBlurEffect(style: lightStyle ? .light : .dark)
            self.effectView.alpha = lightStyle ? 0.85 : 1.0
        })
    }
    
    func animateOut(to rect: CGRect, toNode: ASDisplayNode, completion: @escaping () -> Void) {
        self.keyTextNode.layer.animatePosition(from: self.keyTextNode.layer.position, to: CGPoint(x: rect.midX + 2.0, y: rect.midY), duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, completion: { _ in
            completion()
        })
        self.keyTextNode.layer.animateScale(from: 1.0, to: rect.size.width / (self.keyTextNode.frame.size.width - 2.0), duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
        
        self.titleTextNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false)
        self.infoTextNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false)
        self.buttonNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false)
        
        UIView.animate(withDuration: 0.3, animations: {
            self.effectView.effect = nil
        })
    }
    
    @objc func buttonTapped() {
        self.dismiss()
    }
}

