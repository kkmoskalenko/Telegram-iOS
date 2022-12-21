import AsyncDisplayKit
import AVKit
import SwiftSignalKit
import TelegramVoip

private enum Constants {
    static let cornerRadius: CGFloat = 10.0
    static let glowVideoInset: CGFloat = 50.0
    static let glowRadius: CGFloat = 12.0
    static let glowOpacity: Float = 0.5
}

final class StreamVideoNode: ASDisplayNode {
    
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
    
    func update(size: CGSize) {
        let videoBounds = CGRect(origin: .zero, size: size)
        
        self.groupVideoNode?.updateIsEnabled(true)
        self.groupVideoNode?.frame = videoBounds
        self.groupVideoNode?.updateLayout(size: size, layoutMode: .fit, transition: .immediate)
        
        self.videoGlowView?.updateIsEnabled(true)
        self.videoGlowView?.frame = videoBounds.insetBy(dx: -Constants.glowVideoInset, dy: -Constants.glowVideoInset)
        self.videoGlowMask.frame = videoBounds
        
        let glowPath = UIBezierPath(roundedRect: videoBounds, cornerRadius: Constants.cornerRadius).cgPath
        self.videoGlowMask.path = glowPath
        self.videoGlowMask.shadowPath = glowPath
    }
}
