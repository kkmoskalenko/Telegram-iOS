import AsyncDisplayKit
import AVKit
import Display
import SwiftSignalKit
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
    
    private var groupVideoNode: GroupVideoNode?
    private var videoGlowView: VideoRenderingView?
    
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
    
    init(call: PresentationGroupCallImpl) {
        self.call = call
        super.init()
        
        self.clipsToBounds = false
        self.layer.mask = self.videoGlowMask
    }
    
    func updateVideo() {
        guard self.call.isStream, self.groupVideoNode == nil, let input = self.call.video(endpointId: "unified") else { return }
        
        if let videoView = self.videoRenderingContext.makeView(input: input, blur: false, forceSampleBufferDisplayLayer: true),
           let videoBlurView = self.videoRenderingContext.makeView(input: input, blur: true),
           let videoGlowView = self.videoRenderingContext.makeView(input: input, blur: true) {
            let groupVideoNode = GroupVideoNode(videoView: videoView, backdropVideoView: videoBlurView)
            groupVideoNode.cornerRadius = Constants.cornerRadius
            if #available(iOS 13.0, *) {
                groupVideoNode.layer.cornerCurve = .continuous
            }
            
            self.groupVideoNode = groupVideoNode
            self.videoGlowView = videoGlowView
            
            self.view.addSubview(videoGlowView)
            self.addSubnode(groupVideoNode)
        }
    }
    
    func update(size: CGSize, transition: ContainedViewLayoutTransition) {
        let videoBounds = CGRect(origin: .zero, size: size)
        
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
}
