import Foundation
import UIKit
import AnimatedCountLabelNode
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import TelegramStringFormatting

private let purple = UIColor(rgb: 0x3252ef)
private let pink = UIColor(rgb: 0xef436c)

private let latePurple = UIColor(rgb: 0x974aa9)
private let latePink = UIColor(rgb: 0xf0436c)

final class VoiceChatTimerNode: ASDisplayNode {
    private let strings: PresentationStrings
    private let dateTimeFormat: PresentationDateTimeFormat
    
    private let titleNode: ImmediateTextNode
    private let subtitleNode: ImmediateTextNode
    
    private let timerNode: ImmediateTextNode
    private let participantsNode: ImmediateAnimatedCountLabelNode
    
    private let foregroundView = UIView()
    private let foregroundGradientLayer = CAGradientLayer()
    private let maskView = UIView()
    
    private var validLayout: CGSize?
    
    private var updateTimer: SwiftSignalKit.Timer?
    
    private let hierarchyTrackingNode: HierarchyTrackingNode
    private var isCurrentlyInHierarchy = false
    
    private var isLate = false
    
    init(strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat) {
        self.strings = strings
        self.dateTimeFormat = dateTimeFormat
        
        var updateInHierarchy: ((Bool) -> Void)?
        self.hierarchyTrackingNode = HierarchyTrackingNode({ value in
            updateInHierarchy?(value)
        })
        
        self.titleNode = ImmediateTextNode()
        self.subtitleNode = ImmediateTextNode()
        
        self.timerNode = ImmediateTextNode()
        self.participantsNode = ImmediateAnimatedCountLabelNode()
        self.participantsNode.alwaysOneDirection = true
        
        super.init()
        
        self.addSubnode(self.hierarchyTrackingNode)
        
        self.allowsGroupOpacity = true
        self.isUserInteractionEnabled = false
        
        self.foregroundGradientLayer.type = .radial
        self.foregroundGradientLayer.colors = [pink.cgColor, purple.cgColor, purple.cgColor]
        self.foregroundGradientLayer.locations = [0.0, 0.85, 1.0]
        self.foregroundGradientLayer.startPoint = CGPoint(x: 1.0, y: 0.0)
        self.foregroundGradientLayer.endPoint = CGPoint(x: 0.0, y: 1.0)
        
        self.foregroundView.mask = self.maskView
        self.foregroundView.layer.addSublayer(self.foregroundGradientLayer)
        
        self.view.addSubview(self.foregroundView)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.subtitleNode)
        
        self.maskView.addSubnode(self.timerNode)
        self.maskView.addSubnode(self.participantsNode)
        
        updateInHierarchy = { [weak self] value in
            if let strongSelf = self {
                strongSelf.isCurrentlyInHierarchy = value
                strongSelf.updateAnimations()
            }
        }
    }
    
    deinit {
        self.updateTimer?.invalidate()
    }
    
    func animateIn() {
        self.foregroundView.layer.animateSpring(from: 0.1 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.6, damping: 100.0)
    }
    
    private func updateAnimations() {
        if self.isInHierarchy {
            self.setupGradientAnimations()
        } else {
            self.foregroundGradientLayer.removeAllAnimations()
        }
    }
    
    private func setupGradientAnimations() {
        if let _ = self.foregroundGradientLayer.animation(forKey: "movement") {
        } else {
            let previousValue = self.foregroundGradientLayer.startPoint
            let newValue = CGPoint(x: CGFloat.random(in: 0.65 ..< 0.85), y: CGFloat.random(in: 0.1 ..< 0.45))
            self.foregroundGradientLayer.startPoint = newValue
            
            CATransaction.begin()
            
            let animation = CABasicAnimation(keyPath: "startPoint")
            animation.duration = Double.random(in: 0.8 ..< 1.4)
            animation.fromValue = previousValue
            animation.toValue = newValue
            
            CATransaction.setCompletionBlock { [weak self] in
                if let isCurrentlyInHierarchy = self?.isCurrentlyInHierarchy, isCurrentlyInHierarchy {
                    self?.setupGradientAnimations()
                }
            }
            
            self.foregroundGradientLayer.add(animation, forKey: "movement")
            CATransaction.commit()
        }
    }
    
    func update(size: CGSize, participants: Int32, groupingSeparator: String, transition: ContainedViewLayoutTransition) {
        if self.validLayout == nil {
            self.updateAnimations()
        }
        self.validLayout = size
        
        self.foregroundView.frame = CGRect(origin: CGPoint(), size: size)
        self.foregroundGradientLayer.frame = self.foregroundView.bounds
        self.maskView.frame = self.foregroundView.bounds
        
        self.titleNode.attributedText = nil
        self.timerNode.attributedText = nil
        
        let participantsText = presentationStringsFormattedNumber(participants, groupingSeparator)
        let watchingText = "watching"
        
        var segments = [AnimatedCountLabelNode.Segment]()
        for (index, char) in participantsText.enumerated() {
            let participantsFont = Font.with(size: 45.0, design: .round, weight: .semibold, traits: [.monospacedNumbers])
            let attributedString = NSAttributedString(string: String(char), font: participantsFont, textColor: .white)
            
            if let numberValue = char.wholeNumberValue {
                segments.append(.number(numberValue, attributedString))
            } else {
                segments.append(.text(index, attributedString))
            }
        }
        
        self.participantsNode.segments = segments
        let participantsSize = self.participantsNode.updateLayout(size: CGSize(width: size.width + 100.0, height: size.height), animated: true)
        self.participantsNode.frame = CGRect(x: floor((size.width - participantsSize.width) / 2.0), y: 78.0, width: participantsSize.width, height: participantsSize.height)
        
        self.subtitleNode.attributedText = NSAttributedString(string: watchingText, font: Font.with(size: 16.0, design: .round, weight: .semibold, traits: []), textColor: .white)
        let subtitleSize = self.subtitleNode.updateLayout(size)
        self.subtitleNode.frame = CGRect(x: floor((size.width - subtitleSize.width) / 2.0), y: 132.0, width: subtitleSize.width, height: subtitleSize.height)
        
        self.foregroundView.frame = CGRect(origin: CGPoint(), size: size)
    }
    
    func update(size: CGSize, scheduleTime: Int32?, transition: ContainedViewLayoutTransition) {
        if self.validLayout == nil {
            self.updateAnimations()
        }
        self.validLayout = size
                
        guard let scheduleTime = scheduleTime else {
            return
        }
        
        self.foregroundView.frame = CGRect(origin: CGPoint(), size: size)
        self.foregroundGradientLayer.frame = self.foregroundView.bounds
        self.maskView.frame = self.foregroundView.bounds
        
        let currentTime = Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970)
        let elapsedTime = scheduleTime - currentTime
        let timerText: String
        if elapsedTime >= 86400 {
            timerText = scheduledTimeIntervalString(strings: self.strings, value: elapsedTime)
        } else {
            timerText = textForTimeout(value: abs(elapsedTime))
            if elapsedTime < 0 && !self.isLate {
                self.isLate = true
                self.foregroundGradientLayer.colors = [latePink.cgColor, latePurple.cgColor, latePurple.cgColor]
            }
        }
        
        if self.updateTimer == nil {
            let timer = SwiftSignalKit.Timer(timeout: 0.5, repeat: true, completion: { [weak self] in
                if let strongSelf = self, let size = strongSelf.validLayout {
                    strongSelf.update(size: size, scheduleTime: scheduleTime, transition: .immediate)
                }
            }, queue: Queue.mainQueue())
            self.updateTimer = timer
            timer.start()
        }
        
        let subtitle = humanReadableStringForTimestamp(strings: self.strings, dateTimeFormat: self.dateTimeFormat, timestamp: scheduleTime, alwaysShowTime: true).string
        
        self.titleNode.attributedText = NSAttributedString(string: elapsedTime < 0 ?  self.strings.VoiceChat_LateBy :  self.strings.VoiceChat_StartsIn, font: Font.with(size: 23.0, design: .round, weight: .semibold, traits: []), textColor: .white)
        let titleSize = self.titleNode.updateLayout(size)
        self.titleNode.frame = CGRect(x: floor((size.width - titleSize.width) / 2.0), y: 48.0, width: titleSize.width, height: titleSize.height)
        
        
        self.timerNode.attributedText = NSAttributedString(string: timerText, font: Font.with(size: 68.0, design: .round, weight: .semibold, traits: [.monospacedNumbers]), textColor: .white)
        
        var timerSize = self.timerNode.updateLayout(CGSize(width: size.width + 100.0, height: size.height))
        if timerSize.width > size.width - 32.0 {
            self.timerNode.attributedText = NSAttributedString(string: timerText, font: Font.with(size: 60.0, design: .round, weight: .semibold, traits: [.monospacedNumbers]), textColor: .white)
            timerSize = self.timerNode.updateLayout(CGSize(width: size.width + 100.0, height: size.height))
        }
        
        self.timerNode.frame = CGRect(x: floor((size.width - timerSize.width) / 2.0), y: 78.0, width: timerSize.width, height: timerSize.height)
        
        self.subtitleNode.attributedText = NSAttributedString(string: subtitle, font: Font.with(size: 21.0, design: .round, weight: .semibold, traits: []), textColor: .white)
        let subtitleSize = self.subtitleNode.updateLayout(size)
        self.subtitleNode.frame = CGRect(x: floor((size.width - subtitleSize.width) / 2.0), y: 164.0, width: subtitleSize.width, height: subtitleSize.height)
        
        self.foregroundView.frame = CGRect(origin: CGPoint(), size: size)
    }
}
