import UIKit
import Display
import SwiftSignalKit
import AnimationUI
import AsyncDisplayKit

private enum Constants {
    static let chatItemDefaultHeight: CGFloat = 76.0
    
    static let archiveAvatarSize: CGFloat = 60.0
    static let archiveAvatarVerticalInset: CGFloat = 8.0
    static let archiveAvatarLeadingInset: CGFloat = 10.0
    static let stripWidth: CGFloat = 20.0
    
    static let arrowInitialInset: CGFloat = 16.0
    static let arrowAnchorPoint = CGPoint(x: 0.5, y: 0.565)
    static let arrowInitialColor = UIColor(rgb: 0xB2B2B2)
    static let arrowBlueColor = UIColor(rgb: 0x3F8AF2)
    
    static let greyGradientColors = [
        0xB1B7BE, 0xB9BCC4, 0xD7D7DD
    ].map { UIColor(rgb: $0).cgColor }
    static let greyGradientLocations: [NSNumber] = [0.0, 0.25, 1.0]
    
    static let blueGradientColors = [
        0x057FF0, 0x46A6F8, 0x75C5FC
    ].map { UIColor(rgb: $0).cgColor }
    static let blueGradientLocations: [NSNumber] = [0.0, 0.5, 1.0]
}

final class ChatListArchivePullItem: ListViewItem {
    
    fileprivate enum State {
        case pulling
        case active
        case completed
    }
    
    init(chatListItem: ChatListItem) {
        self.chatListItem = chatListItem
    }
    
    // Model
    fileprivate var chatListItem: ChatListItem
    fileprivate var overscrollAmount: CGFloat = 0.0
    fileprivate var state: State = .pulling
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ChatListArchivePullItemNode()
            
            let (nodeLayout, apply) = node.asyncLayout()(self, params, false)
            
            node.insets = nodeLayout.insets
            node.contentSize = nodeLayout.contentSize
            
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in
                        apply()
                    })
                })
            }
        }
    }
    
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            assert(node() is ChatListArchivePullItemNode)
            if let nodeValue = node() as? ChatListArchivePullItemNode {
                
                let layout = nodeValue.asyncLayout()
                async {
                    let (nodeLayout, apply) = layout(self, params, nextItem == nil)
                    Queue.mainQueue().async {
                        completion(nodeLayout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

final class ChatListArchivePullItemNode: ListViewItemNode {
    
    // Model
    private var item: ChatListArchivePullItem?
    private var isAnimating = false
    
    // UI
    private lazy var animationNode: AnimationNode = {
        let animationNode = AnimationNode(animation: "anim_archivePull", colors: ["**.Fill 1": .white, "**.Stroke 1": Constants.arrowInitialColor])
        animationNode.transform = CATransform3DMakeAffineTransform(CGAffineTransform(rotationAngle: .pi))
        animationNode.anchorPoint = Constants.arrowAnchorPoint
        animationNode.isUserInteractionEnabled = false
        return animationNode
    }()
    
    private lazy var swipeTextNode: ImmediateTextNode = {
        let textNode = ImmediateTextNode()
        textNode.attributedText = NSAttributedString(string: "Swipe down for archive", attributes: [
            .font: UIFont.boldSystemFont(ofSize: 17.0),
            .foregroundColor: UIColor.white
        ])
        textNode.isUserInteractionEnabled = false
        return textNode
    }()
    
    private lazy var releaseTextNode: ImmediateTextNode = {
        let textNode = ImmediateTextNode()
        textNode.attributedText = NSAttributedString(string: "Release for archive", attributes: [
            .font: UIFont.boldSystemFont(ofSize: 17.0),
            .foregroundColor: UIColor.white
        ])
        textNode.isUserInteractionEnabled = false
        textNode.alpha = 0.0
        return textNode
    }()
    
    private lazy var textContainerNode: ASDisplayNode = {
        let node = ASDisplayNode()
        let mask = CALayer()
        mask.backgroundColor = UIColor.black.cgColor
        node.layer.mask = mask
        node.addSubnode(swipeTextNode)
        node.addSubnode(releaseTextNode)
        return node
    }()
    
    private lazy var backgroundStripNode: ASDisplayNode = {
        let node = ASDisplayNode()
        node.cornerRadius = Constants.stripWidth / 2.0
        node.backgroundColor = UIColor.white
        node.alpha = 0.3
        node.isUserInteractionEnabled = false
        return node
    }()
    
    private lazy var backgroundGradient: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .axial
        gradient.colors = Constants.greyGradientColors
        gradient.locations = Constants.greyGradientLocations
        gradient.startPoint = CGPoint(x: 0.0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.0, y: 0.5)
        return gradient
    }()
    
    private lazy var foregroundGradient: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.colors = Constants.blueGradientColors
        gradient.locations = Constants.blueGradientLocations
        gradient.mask = circleMaskLayer
        return gradient
    }()
    
    private lazy var circleMaskLayer: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = UIColor.black.cgColor
        layer.transform = CATransform3DMakeScale(0.01, 0.01, 0.01)
        return layer
    }()
    
    // MARK: - Initializers
    
    init() {
        super.init(layerBacked: false, dynamicBounce: false)
        
        layer.addSublayer(backgroundGradient)
        layer.addSublayer(foregroundGradient)
        
        addSubnode(backgroundStripNode)
        addSubnode(animationNode)
        addSubnode(textContainerNode)
    }
    
    // MARK: - Layout
    
    override func layoutForParams(_ params: ListViewItemLayoutParams, item: ListViewItem, previousItem: ListViewItem?, nextItem: ListViewItem?) {
        let layout = self.asyncLayout()
        let (_, apply) = layout(item as! ChatListArchivePullItem, params, nextItem == nil)
        apply()
    }
    
    func asyncLayout() -> (_ item: ChatListArchivePullItem, _ params: ListViewItemLayoutParams, _ isLast: Bool) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, last in
            let height = item.state == .completed ? Constants.chatItemDefaultHeight : item.overscrollAmount
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height), insets: .zero)
            
            return (layout, { [weak self] in
                guard let strongSelf = self else { return }
                
                strongSelf.item = item
                strongSelf.contentSize = layout.contentSize
                strongSelf.insets = layout.insets
                
                strongSelf.updateLayout()
            })
        }
    }
    
    func updateOverscrollAmount(_ value: CGFloat, isDragging: Bool) {
        guard let item, item.overscrollAmount != value else { return }
        item.overscrollAmount = value
        
        if value > Constants.chatItemDefaultHeight {
            transitionToActiveState()
        } else if isDragging {
            transitionToPullingState()
        } else {
            transitionToCompletedState(completion: {
                // TODO: Display the actual archive item
            })
        }
        
        if let listNode = self.supernode as? ChatListNode,
           let index = self.index, let item = self.item
        {
            let updateItem = ListViewUpdateItem(index: index, previousIndex: index, item: item, directionHint: nil)
            listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [updateItem], options: [], updateOpaqueState: nil)
        }
    }
    
    // MARK: - Private
    
    private func updateLayout() {
        let contentRect = CGRect(origin: .zero, size: contentSize)
        
        if item?.state != .completed {
            animationNode.frame = CGRect(origin: CGPoint(x: Constants.archiveAvatarLeadingInset,
                                                         y: Constants.arrowInitialInset + contentSize.height - Constants.archiveAvatarSize - Constants.archiveAvatarVerticalInset),
                                         size: CGSize(width: Constants.archiveAvatarSize, height: Constants.archiveAvatarSize))
        }
        
        textContainerNode.frame = contentRect
        
        let swipeTextSize = swipeTextNode.updateLayout(contentSize)
        let swipeTextOrigin = CGPoint(x: (contentSize.width - swipeTextSize.width) / 2.0,
                                 y: contentSize.height - swipeTextSize.height - Constants.archiveAvatarVerticalInset)
        swipeTextNode.frame = CGRect(origin: swipeTextOrigin, size: swipeTextSize)
        
        let releaseTextSize = releaseTextNode.updateLayout(contentSize)
        let releaseTextOrigin = CGPoint(x: (contentSize.width - releaseTextSize.width) / 2.0,
                                        y: contentSize.height - releaseTextSize.height - Constants.archiveAvatarVerticalInset)
        releaseTextNode.frame = CGRect(origin: releaseTextOrigin, size: releaseTextSize)
        
        let stripSize = CGSize(width: Constants.stripWidth,
                               height: max(0.0, contentSize.height - 2.0 * Constants.archiveAvatarVerticalInset))
        let stripOrigin = CGPoint(x: Constants.archiveAvatarLeadingInset + (Constants.archiveAvatarSize - stripSize.width) / 2.0,
                                  y: Constants.archiveAvatarVerticalInset)
        backgroundStripNode.frame = CGRect(origin: stripOrigin, size: stripSize)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundGradient.frame = contentRect
        
        let circleCenter = CGPoint(x: Constants.archiveAvatarLeadingInset + 30.0, y: item?.state == .completed ?
                                   Constants.archiveAvatarVerticalInset + Constants.archiveAvatarSize / 2.0 :
                                    contentSize.height - Constants.archiveAvatarVerticalInset - 10.0)
        let circleRadius = max(contentSize.width, contentSize.height)
        
        foregroundGradient.frame = contentRect
        foregroundGradient.startPoint = CGPoint(x: circleCenter.x / contentSize.width, y: circleCenter.y / contentSize.height)
        foregroundGradient.endPoint = CGPoint(x: 1.0, y: contentSize.width / contentSize.height)
        
        circleMaskLayer.frame = CGRect(x: circleCenter.x - circleRadius, y: circleCenter.y - circleRadius,
                                       width: 2 * circleRadius, height: 2 * circleRadius)
        circleMaskLayer.cornerRadius = circleRadius
        
        let textMaskFrame = contentRect.inset(by: UIEdgeInsets(top: 0.0, left: stripOrigin.x + stripSize.width, bottom: 0.0, right: 0.0))
        textContainerNode.layer.mask?.frame = textMaskFrame
        
        CATransaction.commit()
    }
    
    private func transitionToActiveState() {
        guard !isAnimating, item?.state == .pulling else { return }
        isAnimating = true
        item?.state = .active
        
        animationNode.setProgress(0.0)
        
        circleMaskLayer.animateScale(from: 0.01, to: 1.0, duration: 0.2, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false) { [weak self] _ in
            self?.isAnimating = false
        }
        
        animationNode.anchorPoint = Constants.arrowAnchorPoint
        animationNode.layer.animateRotation(from: .pi, to: .zero, duration: 0.2, removeOnCompletion: false) { [weak self] _ in
            self?.animationNode.setColors(colors: ["**.Stroke 1": Constants.arrowBlueColor])
        }
        
        let transition = ContainedViewLayoutTransition.animated(duration: 0.2, curve: .spring)
        transition.updateTransform(node: swipeTextNode, transform: CGAffineTransform(translationX: swipeTextNode.frame.maxX, y: 0.0))
        transition.updateAlpha(node: swipeTextNode, alpha: 0.0)
        
        let releaseTextTransform = CGAffineTransform(translationX: -releaseTextNode.frame.maxX, y: 0.0)
        releaseTextNode.transform = CATransform3DMakeAffineTransform(releaseTextTransform)
        transition.updateTransform(node: releaseTextNode, transform: .identity)
        transition.updateAlpha(node: releaseTextNode, alpha: 1.0)
    }
    
    private func transitionToPullingState() {
        guard !isAnimating, item?.state == .active else { return }
        isAnimating = true
        item?.state = .pulling
        
        animationNode.setProgress(0.0)
        
        circleMaskLayer.animateScale(from: 1.0, to: 0.01, duration: 0.2, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false) { [weak self] _ in
            self?.isAnimating = false
        }
        
        animationNode.anchorPoint = Constants.arrowAnchorPoint
        animationNode.layer.animateRotation(from: .zero, to: .pi, duration: 0.2, removeOnCompletion: false) { [weak self] _ in
            self?.animationNode.setColors(colors: ["**.Stroke 1": Constants.arrowInitialColor])
        }
        
        let transition = ContainedViewLayoutTransition.animated(duration: 0.2, curve: .spring)
        transition.updateTransform(node: swipeTextNode, transform: .identity)
        transition.updateAlpha(node: swipeTextNode, alpha: 1.0)
        
        let releaseTextTransform = CGAffineTransform(translationX: -releaseTextNode.frame.maxX, y: 0.0)
        transition.updateTransform(node: releaseTextNode, transform: releaseTextTransform)
        transition.updateAlpha(node: releaseTextNode, alpha: 0.0)
    }
    
    private func transitionToCompletedState(completion: (() -> Void)? = nil) {
        guard !isAnimating, item?.state == .active else { return }
        isAnimating = true
        item?.state = .completed
        
        backgroundGradient.isHidden = true
        animationNode.playOnce()
        
        let newScale = 0.5 * Constants.archiveAvatarSize / max(contentSize.width, contentSize.height)
        circleMaskLayer.animateScale(from: 1.0, to: newScale, duration: 0.2, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false) { [weak self] _ in
            self?.isAnimating = false
            completion?()
        }
        
        let transition = ContainedViewLayoutTransition.animated(duration: 0.1, curve: .spring)
        transition.updateAnchorPoint(layer: animationNode.layer, anchorPoint: CGPoint(x: 0.5, y: 0.5))
        transition.updateFrameAdditiveToCenter(node: animationNode, frame: CGRect(
            origin: CGPoint(x: Constants.archiveAvatarLeadingInset, y: Constants.archiveAvatarVerticalInset),
            size: CGSize(width: Constants.archiveAvatarSize, height: Constants.archiveAvatarSize)
        ))
        transition.updateAlpha(node: releaseTextNode, alpha: 0.0)
        transition.updateAlpha(node: backgroundStripNode, alpha: 0.0)
    }
}
