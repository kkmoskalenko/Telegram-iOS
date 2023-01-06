import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import ChatTitleActivityNode

private let constructiveColor: UIColor = UIColor(rgb: 0x34c759)
private let liveStreamActiveColor: UIColor = UIColor(rgb: 0xf42d53)
private let liveStreamLoadingColor: UIColor = UIColor(rgb: 0x9c9c9c)

final class VoiceChatTitleNode: ASDisplayNode {
    
    private let titleNode: ASTextNode
    private let infoNode: ChatTitleActivityNode
    let recordingIconNode: VoiceChatRecordingIconNode
    let liveIndicatorNode: VoiceChatLiveIndicatorNode
    
    public var isRecording: Bool = false {
        didSet {
            self.recordingIconNode.isHidden = !self.isRecording
        }
    }
    
    public var isLivestreamActive: Bool {
        get { self.liveIndicatorNode.isLivestreamActive }
        set { self.liveIndicatorNode.isLivestreamActive = newValue }
    }
    
    var tapped: (() -> Void)?
    
    override init() {
        self.titleNode = ASTextNode()
        self.titleNode.displaysAsynchronously = false
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.truncationMode = .byTruncatingTail
        self.titleNode.isOpaque = false
        
        self.infoNode = ChatTitleActivityNode()
        
        self.recordingIconNode = VoiceChatRecordingIconNode(hasBackground: false)
        
        self.liveIndicatorNode = VoiceChatLiveIndicatorNode()
        self.liveIndicatorNode.isHidden = true
        
        super.init()
        
        self.addSubnode(self.titleNode)
        self.addSubnode(self.infoNode)
        self.addSubnode(self.recordingIconNode)
        self.addSubnode(self.liveIndicatorNode)
    }
        
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tap)))
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if point.y > 0.0 && point.y < self.frame.size.height && point.x > min(self.titleNode.frame.minX, self.infoNode.frame.minX) && point.x < max(self.recordingIconNode.frame.maxX, self.infoNode.frame.maxX) {
            return true
        } else {
            return false
        }
    }
    
    @objc private func tap() {
        self.tapped?()
    }
    
    func update(size: CGSize, title: String, subtitle: String, speaking: Bool, slide: Bool, transition: ContainedViewLayoutTransition) {
        guard !size.width.isZero else {
            return
        }
        var titleUpdated = false
        if let previousTitle = self.titleNode.attributedText?.string {
            titleUpdated = previousTitle != title
        }
        
        if titleUpdated, let snapshotView = self.titleNode.view.snapshotContentTree() {
            snapshotView.frame = self.titleNode.frame
            self.view.addSubview(snapshotView)
            
            snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                snapshotView?.removeFromSuperview()
            })
            
            self.titleNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
            
            if slide {
                self.infoNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                let offset: CGFloat = 16.0
                snapshotView.layer.animatePosition(from: CGPoint(), to: CGPoint(x: 0.0, y: -offset), duration: 0.2, removeOnCompletion: false, additive: true)
                self.titleNode.layer.animatePosition(from: CGPoint(x: 0.0, y: offset), to: CGPoint(), duration: 0.2, additive: true)
                self.infoNode.layer.animatePosition(from: CGPoint(x: 0.0, y: offset), to: CGPoint(), duration: 0.2, additive: true)
            }
        }
        
        self.titleNode.attributedText = NSAttributedString(string: title, font: Font.medium(17.0), textColor: UIColor(rgb: 0xffffff))
        self.infoNode.isHidden = false
        self.liveIndicatorNode.isHidden = true
            
        var state = ChatTitleActivityNodeState.none
        if speaking {
            state = .recordingVoice(NSAttributedString(string: subtitle, font: Font.regular(13.0), textColor: constructiveColor), constructiveColor)
        } else {
            state = .info(NSAttributedString(string: subtitle, font: Font.regular(13.0), textColor: UIColor(rgb: 0xffffff, alpha: 0.5)), .generic)
        }
        let _ = self.infoNode.transitionToState(state, animation: .slide)
        
        let constrainedSize = CGSize(width: size.width - 140.0, height: size.height)
        let titleSize = self.titleNode.measure(constrainedSize)
        let infoSize = self.infoNode.updateLayout(constrainedSize, offset: 1.0, alignment: .center)
        let titleInfoSpacing: CGFloat = 0.0
        
        let combinedHeight = titleSize.height + infoSize.height + titleInfoSpacing
        
        let titleFrame = CGRect(origin: CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: floor((size.height - combinedHeight) / 2.0)), size: titleSize)
        self.titleNode.frame = titleFrame
        self.infoNode.frame = CGRect(origin: CGPoint(x: floor((size.width - infoSize.width) / 2.0), y: floor((size.height - combinedHeight) / 2.0) + titleSize.height + titleInfoSpacing), size: infoSize)
        
        let iconSide = 16.0 + (1.0 + UIScreenPixel) * 2.0
        let iconSize: CGSize = CGSize(width: iconSide, height: iconSide)
        self.recordingIconNode.frame = CGRect(origin: CGPoint(x: titleFrame.maxX + 1.0, y: titleFrame.minY + 1.0), size: iconSize)
    }
    
    func update(size: CGSize, title: String) {
        guard !size.width.isZero else { return }
        
        self.titleNode.attributedText = NSAttributedString(string: title, font: Font.medium(17.0), textColor: UIColor(rgb: 0xffffff))
        self.infoNode.isHidden = true
        self.liveIndicatorNode.isHidden = false
        
        let constrainedSize = CGSize(width: size.width - 181.0, height: size.height)
        let titleSize = self.titleNode.measure(constrainedSize)
        let indicatorSize = CGSize(width: 35.0, height: 20.0)
        let indicatorOffset: CGFloat = 6.0
        
        let titleFrame = CGRect(origin: CGPoint(x: floor((size.width - titleSize.width - indicatorSize.width - indicatorOffset) / 2.0), y: floor((size.height - titleSize.height) / 2.0)), size: titleSize)
        let indicatorFrame = CGRect(origin: CGPoint(x: titleFrame.maxX + indicatorOffset, y: titleFrame.minY), size: indicatorSize)
        
        self.titleNode.frame = titleFrame
        self.liveIndicatorNode.frame = indicatorFrame
        
        let iconSide = 16.0 + (1.0 + UIScreenPixel) * 2.0
        let iconSize = CGSize(width: iconSide, height: iconSide)
        self.recordingIconNode.frame = CGRect(origin: CGPoint(x: indicatorFrame.maxX + 1.0, y: titleFrame.minY + 1.0), size: iconSize)
    }
}

// MARK: - Live Indicator

final class VoiceChatLiveIndicatorNode: ASDisplayNode {
    private let backgroundNode: ASDisplayNode
    private let textNode: ASTextNode
    
    private let indicatorText = "LIVE"
    private let textFont = Font.with(size: 11.0, design: .round, weight: .bold, traits: [])
    
    var isLivestreamActive: Bool = false {
        didSet {
            guard self.isLivestreamActive != oldValue else { return }
            
            let transition = ContainedViewLayoutTransition.animated(duration: 0.15, curve: .easeInOut)
            let newColor = self.isLivestreamActive ? liveStreamActiveColor : liveStreamLoadingColor
            
            transition.updateTransformScale(node: self, scale: 1.2, completion: { _ in
                let transition = ContainedViewLayoutTransition.animated(duration: 0.1, curve: .easeInOut)
                transition.updateTransformScale(node: self, scale: 1.0)
                transition.updateBackgroundColor(node: self.backgroundNode, color: newColor)
            })
        }
    }
    
    override init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.displaysAsynchronously = false
        self.backgroundNode.isLayerBacked = true
        
        self.backgroundNode.backgroundColor = liveStreamLoadingColor
        
        self.textNode = ASTextNode()
        self.textNode.attributedText = NSAttributedString(string: indicatorText, font: textFont, textColor: .white)
        self.textNode.textAlignment = .center
        self.textNode.verticalAlignment = .middle
        self.textNode.displaysAsynchronously = false
        self.textNode.isLayerBacked = true
        
        super.init()
        
        self.isLayerBacked = true
        self.clipsToBounds = true
        
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.textNode)
    }
    
    override func layout() {
        super.layout()
      
        self.cornerRadius = self.bounds.size.height / 2.0
        
        self.backgroundNode.frame = self.bounds
        self.textNode.frame = self.bounds
    }
}
