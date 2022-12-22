import AsyncDisplayKit
import AvatarNode
import AVKit
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramVoip

private enum Constants {
    static let cornerRadius: CGFloat = 10.0
    static let glowVideoInset: CGFloat = 50.0
    static let glowRadius: CGFloat = 12.0
    static let glowOpacity: Float = 0.5
}

final class StreamVideoNode: ASDisplayNode {
    
    var tapped: (() -> Void)? {
        get { self.groupVideoNode?.tapped }
        set { self.groupVideoNode?.tapped = newValue }
    }
    
    var isLandscape: Bool {
        (groupVideoNode?.aspectRatio ?? 1.0) < 1.0
    }
    
    var onVideoReady: (() -> Void)?
    
    private var groupVideoNode: GroupVideoNode?
    private var videoGlowView: VideoRenderingView?
    private var shimmeringNode: StreamShimmeringNode?
    
    private lazy var videoGlowMask: CAShapeLayer = {
        let shapeLayer = CAShapeLayer()
        shapeLayer.fillColor = UIColor.white.cgColor
        shapeLayer.shadowColor = UIColor.white.cgColor
        shapeLayer.shadowRadius = Constants.glowRadius
        shapeLayer.shadowOpacity = Constants.glowOpacity
        return shapeLayer
    }()
    
    private let call: PresentationGroupCallImpl
    private let videoRenderingContext = VideoRenderingContext()
    
    private var videoReady: Bool = false
    private var disposable: Disposable?
    
    init(call: PresentationGroupCallImpl) {
        self.call = call
        super.init()
        
        self.clipsToBounds = false
        self.layer.mask = self.videoGlowMask
    }
    
    deinit {
        self.disposable?.dispose()
    }
    
    func updatePeer(_ peer: Peer) {
        guard self.shimmeringNode == nil, !self.videoReady else { return }
        
        let shimmeringNode = StreamShimmeringNode(account: self.call.account, peer: peer)
        shimmeringNode.isUserInteractionEnabled = false
        self.addSubnode(shimmeringNode)
        self.shimmeringNode = shimmeringNode
    }
    
    func updateVideo(pictureInPictureControllerDelegate: AVPictureInPictureControllerDelegate? = nil) {
        guard self.call.isStream, self.groupVideoNode == nil, let input = self.call.video(endpointId: "unified") else { return }
        
        if let videoView = self.videoRenderingContext.makeView(input: input, blur: false, forceSampleBufferDisplayLayer: true),
           let videoBlurView = self.videoRenderingContext.makeView(input: input, blur: true),
           let videoGlowView = self.videoRenderingContext.makeView(input: input, blur: true) {
            let groupVideoNode = GroupVideoNode(videoView: videoView, backdropVideoView: videoBlurView)
            groupVideoNode.setupPictureInPicture(delegate: pictureInPictureControllerDelegate)
            groupVideoNode.cornerRadius = Constants.cornerRadius
            if #available(iOS 13.0, *) {
                groupVideoNode.layer.cornerCurve = .continuous
            }
            self.disposable = groupVideoNode.ready.start(next: { [weak self] ready in
                self?.videoReady = ready
                if ready {
                    self?.onVideoReady?()
                }
                
                if let shimmerNode = self?.shimmeringNode, ready {
                    DispatchQueue.main.async {
                        self?.shimmeringNode = nil
                        shimmerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak shimmerNode] _ in
                            shimmerNode?.removeFromSupernode()
                        })
                    }
                }
            })
            
            self.groupVideoNode = groupVideoNode
            self.videoGlowView = videoGlowView
            
            self.view.insertSubview(videoGlowView, at: 0)
            if let shimmeringNode = self.shimmeringNode {
                self.insertSubnode(groupVideoNode, belowSubnode: shimmeringNode)
            } else {
                self.addSubnode(groupVideoNode)
            }
        }
    }
    
    func update(size: CGSize, transition: ContainedViewLayoutTransition) {
        let videoBounds = CGRect(origin: .zero, size: size)
        
        if let shimmerNode = self.shimmeringNode {
            let shimmerTransition: ContainedViewLayoutTransition
            if shimmerNode.bounds.isEmpty {
                shimmerTransition = .immediate
            } else {
                shimmerTransition = transition
            }
            
            shimmerTransition.updateFrame(node: shimmerNode, frame: videoBounds)
            shimmerNode.updateAbsoluteRect(videoBounds, within: size)
            shimmerNode.update(shimmeringColor: UIColor.white, shimmering: !self.videoReady, size: size, transition: transition)
        }
        
        if let videoNode = self.groupVideoNode {
            videoNode.updateIsEnabled(true)
            videoNode.updateLayout(size: size, layoutMode: .fit, transition: transition)
            transition.updateFrame(node: videoNode, frame: videoBounds)
        }
        
        if let glowView = self.videoGlowView {
            glowView.updateIsEnabled(true)
            let glowViewFrame = videoBounds.insetBy(dx: -Constants.glowVideoInset, dy: -Constants.glowVideoInset)
            transition.updateFrame(view: glowView, frame: glowViewFrame)
        }
        
        let glowPath = UIBezierPath(roundedRect: videoBounds, cornerRadius: Constants.cornerRadius).cgPath
        self.videoGlowMask.shadowPath = glowPath
        transition.updatePath(layer: self.videoGlowMask, path: glowPath)
        transition.updateFrame(layer: self.videoGlowMask, frame: videoBounds)
    }
    
    func startPictureInPicture() {
        self.groupVideoNode?.startPictureInPicture()
    }
    
    func stopPictureInPicture() {
        self.groupVideoNode?.stopPictureInPicture()
    }
    
    func updateVideoViewIsEnabledForPictureInPicture() {
        self.groupVideoNode?.updateVideoViewIsEnabledForPictureInPicture()
    }
}

private final class StreamShimmeringNode: ASDisplayNode {
    
    private let backgroundNode: ImageNode
    private let effectNode: ShimmerEffectForegroundNode
    
    private let borderNode: ASDisplayNode
    private var borderMaskView: UIView?
    private let borderEffectNode: ShimmerEffectForegroundNode
    
    private var currentShimmeringColor: UIColor?
    private var currentShimmering: Bool?
    private var currentSize: CGSize?
    
    public init(account: Account, peer: Peer) {
        self.backgroundNode = ImageNode(enableHasImage: false, enableEmpty: false, enableAnimatedTransition: true)
        self.backgroundNode.displaysAsynchronously = false
        self.backgroundNode.contentMode = .scaleAspectFill
        
        self.effectNode = ShimmerEffectForegroundNode(size: 240.0)
        
        self.borderNode = ASDisplayNode()
        self.borderEffectNode = ShimmerEffectForegroundNode(size: 320.0)
        
        super.init()
        
        self.clipsToBounds = true
        self.cornerRadius = Constants.cornerRadius
        
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.effectNode)
        self.addSubnode(self.borderNode)
        self.borderNode.addSubnode(self.borderEffectNode)
        
        self.backgroundNode.setSignal(peerAvatarCompleteImage(account: account, peer: EnginePeer(peer), size: CGSize(width: 250.0, height: 250.0), round: false, font: Font.regular(16.0), drawLetters: false, fullSize: false, blurred: true))
    }
    
    public override func didLoad() {
        super.didLoad()
        
        if self.effectNode.supernode != nil {
            self.effectNode.layer.compositingFilter = "screenBlendMode"
            self.borderEffectNode.layer.compositingFilter = "screenBlendMode"
            
            let borderMaskView = UIView()
            borderMaskView.layer.borderWidth = 2.0
            borderMaskView.layer.borderColor = UIColor.white.cgColor
            borderMaskView.layer.cornerRadius = Constants.cornerRadius
            self.borderMaskView = borderMaskView
            
            if let size = self.currentSize {
                borderMaskView.frame = CGRect(origin: CGPoint(), size: size)
            }
            self.borderNode.view.mask = borderMaskView
            
            if #available(iOS 13.0, *) {
                borderMaskView.layer.cornerCurve = .continuous
            }
        }
        if #available(iOS 13.0, *) {
            self.layer.cornerCurve = .continuous
        }
    }
    
    public func updateAbsoluteRect(_ rect: CGRect, within containerSize: CGSize) {
        self.effectNode.updateAbsoluteRect(rect, within: containerSize)
        self.borderEffectNode.updateAbsoluteRect(rect, within: containerSize)
    }
    
    public func update(shimmeringColor: UIColor, shimmering: Bool, size: CGSize, transition: ContainedViewLayoutTransition) {
        if let currentShimmeringColor = self.currentShimmeringColor, currentShimmeringColor.isEqual(shimmeringColor) && self.currentSize == size && self.currentShimmering == shimmering {
            return
        }
        
        let firstTime = self.currentShimmering == nil
        self.currentShimmeringColor = shimmeringColor
        self.currentShimmering = shimmering
        self.currentSize = size
        
        let transition: ContainedViewLayoutTransition = firstTime ? .immediate : (transition.isAnimated ? transition : .animated(duration: 0.45, curve: .easeInOut))
        transition.updateAlpha(node: self.effectNode, alpha: shimmering ? 1.0 : 0.0)
        transition.updateAlpha(node: self.borderNode, alpha: shimmering ? 1.0 : 0.0)
        
        let bounds = CGRect(origin: CGPoint(), size: size)
        
        self.effectNode.update(foregroundColor: shimmeringColor.withAlphaComponent(0.3))
        transition.updateFrame(node: self.effectNode, frame: bounds)
        
        self.borderEffectNode.update(foregroundColor: shimmeringColor.withAlphaComponent(0.45))
        transition.updateFrame(node: self.borderEffectNode, frame: bounds)
        
        transition.updateFrame(node: self.backgroundNode, frame: bounds)
        transition.updateFrame(node: self.borderNode, frame: bounds)
        if let borderMaskView = self.borderMaskView {
            transition.updateFrame(view: borderMaskView, frame: bounds)
        }
    }
}
