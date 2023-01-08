import AccountContext
import AnimatedCountLabelNode
import AsyncDisplayKit
import AvatarNode
import AVKit
import Display
import FastBlur
import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramVoip
import VideoToolbox

private enum Constants {
    static let cornerRadius: CGFloat = 10.0
    static let glowVideoInset: CGFloat = 50.0
    static let glowRadius: CGFloat = 12.0
    static let glowOpacity: Float = 0.5
    static let noSignalTimeout: TimeInterval = 0.5
    static let noSignalMessageTimeout: TimeInterval = 20.0
    static let fullscreenBarHeight: CGFloat = 44.0
}

final class StreamVideoNode: ASDisplayNode {
    
    var onVideoReadyChanged: ((Bool) -> Void)?
    
    var visibility: Bool = false {
        didSet {
            guard oldValue != self.visibility else { return }
            
            self.groupVideoNode?.updateIsEnabled(self.visibility)
            self.videoGlowView?.updateIsEnabled(self.visibility)
            self.videoRenderingContext.updateVisibility(isVisible: self.visibility)
            
            if self.pictureInPictureController?.isPictureInPictureActive == true {
                self.videoView?.updateIsEnabled(true)
            }
            
            if !self.visibility {
                storeLastFrameThumbnail()
            }
        }
    }
    
    private var groupVideoNode: GroupVideoNode?
    private var videoGlowView: VideoRenderingView?
    private var shimmeringNode: StreamShimmeringNode?
    private weak var videoView: VideoRenderingView?
    
    private lazy var videoGlowMask: CAShapeLayer = {
        let shapeLayer = CAShapeLayer()
        shapeLayer.fillColor = UIColor.white.cgColor
        shapeLayer.shadowColor = UIColor.white.cgColor
        shapeLayer.shadowOffset = .zero
        shapeLayer.shadowRadius = Constants.glowRadius
        shapeLayer.shadowOpacity = 0.0
        return shapeLayer
    }()
    
    private lazy var noSignalTextNode: ASTextNode = {
        let textNode = ASTextNode()
        textNode.textAlignment = .center
        textNode.verticalAlignment = .middle
        textNode.maximumNumberOfLines = 0
        textNode.alpha = 0.0
        textNode.isUserInteractionEnabled = false
        return textNode
    }()
    
    private let call: PresentationGroupCallImpl
    private let strings: PresentationStrings
    
    private let videoRenderingContext = VideoRenderingContext()
    
    private var videoReady: Bool = false
    private var disposable: Disposable?
    
    private var noSignalTimer: Foundation.Timer?
    private var noSignalDuration: TimeInterval = 0.0 {
        didSet {
            self.updateNoSignalMessageVisible(self.noSignalDuration >= Constants.noSignalMessageTimeout)
        }
    }
    
    // MARK: Initializers
    
    init(call: PresentationGroupCallImpl, strings: PresentationStrings) {
        self.call = call
        self.strings = strings
        super.init()
        
        self.clipsToBounds = false
        self.layer.mask = self.videoGlowMask
        
        self.fullscreenOverlayNode.alpha = 0.0
        self.addSubnode(self.fullscreenOverlayNode)
        
        self.insertSubnode(self.noSignalTextNode, aboveSubnode: fullscreenOverlayNode)
    }
    
    deinit {
        self.disposable?.dispose()
        self.noSignalTimer?.invalidate()
    }
    
    // MARK: Update Methods
    
    func updateVideo(pictureInPictureControllerDelegate: AVPictureInPictureControllerDelegate? = nil) {
        guard self.call.isStream, self.groupVideoNode == nil, let input = self.call.video(endpointId: "unified") else { return }
        
        if let videoView = self.videoRenderingContext.makeView(input: input, blur: false, forceSampleBufferDisplayLayer: true),
           let videoBlurView = self.videoRenderingContext.makeView(input: input, blur: true),
           let videoGlowView = self.videoRenderingContext.makeView(input: input, blur: true) {
            let groupVideoNode = GroupVideoNode(videoView: videoView, backdropVideoView: videoBlurView)
            groupVideoNode.tapped = { [weak self] in
                if self?.isFullscreen == true {
                    self?.displayUI.toggle()
                }
            }
            groupVideoNode.cornerRadius = Constants.cornerRadius
            if #available(iOS 13.0, *) {
                groupVideoNode.layer.cornerCurve = .continuous
            }
            self.disposable = groupVideoNode.ready.start(next: { [weak self] ready in
                self?.updateVideoReady(ready)
            })
            self.noSignalTimer = .scheduledTimer(withTimeInterval: Constants.noSignalTimeout, repeats: true) { [weak self] timer in
                guard let renderingView = self?.videoView else {
                    timer.invalidate()
                    return
                }
                
                let timestampDelta = CFAbsoluteTimeGetCurrent() - renderingView.getLastFrameTimestamp()
                let videoReady = timestampDelta <= Constants.noSignalTimeout
                self?.updateVideoReady(videoReady)
                
                if videoReady {
                    self?.noSignalDuration = 0.0
                } else {
                    self?.noSignalDuration += Constants.noSignalTimeout
                }
            }
            
            self.groupVideoNode = groupVideoNode
            self.videoGlowView = videoGlowView
            self.videoView = videoView
            
            self.setupPictureInPicture(delegate: pictureInPictureControllerDelegate)
            
            self.view.insertSubview(videoGlowView, at: 0)
            if let shimmeringNode = self.shimmeringNode {
                self.insertSubnode(groupVideoNode, belowSubnode: shimmeringNode)
            } else {
                self.insertSubnode(groupVideoNode, belowSubnode: self.fullscreenOverlayNode)
            }
            
            groupVideoNode.updateIsEnabled(self.visibility)
            videoGlowView.updateIsEnabled(self.visibility)
        }
    }
    
    func update(size: CGSize, safeInsets: UIEdgeInsets, transition: ContainedViewLayoutTransition, isFullscreen: Bool, peer: Peer?) {
        let videoBounds = CGRect(origin: .zero, size: size)
        
        if !isFullscreen {
            self.fullscreenOverlayNode.alpha = 0.0
        }
        self.isFullscreen = isFullscreen
        
        if self.shimmeringNode == nil, !self.videoReady, let peer = peer {
            let thumbnailImage = UIImage(contentsOfFile: self.cachedThumbnailPath)
            let shimmeringNode = StreamShimmeringNode(account: self.call.account, peer: peer, image: thumbnailImage)
            shimmeringNode.isUserInteractionEnabled = false
            self.insertSubnode(shimmeringNode, belowSubnode: self.fullscreenOverlayNode)
            self.shimmeringNode = shimmeringNode
        }
        
        if let shimmerNode = self.shimmeringNode {
            let shimmerTransition: ContainedViewLayoutTransition
            if shimmerNode.bounds.isEmpty {
                shimmerTransition = .immediate
            } else {
                shimmerTransition = transition
            }
            
            shimmerTransition.updateFrame(node: shimmerNode, frame: videoBounds)
            shimmerNode.updateAbsoluteRect(videoBounds, within: size)
            shimmerNode.update(shimmeringColor: UIColor.white, shimmering: true, size: size, transition: transition)
        }
        
        self.fullscreenOverlayNode.update(size: size, safeInsets: safeInsets, transition: transition)
        transition.updateFrame(node: self.fullscreenOverlayNode, frame: videoBounds)
        
        let noSignalText = NSAttributedString(string: self.fullscreenOverlayNode.canManageCall ? self.strings.LiveStream_NoSignalAdminText : self.strings.LiveStream_NoSignalUserText(self.fullscreenOverlayNode.title).string, font: .systemFont(ofSize: 16.0), textColor: .white)
        self.noSignalTextNode.attributedText = noSignalText
        let noSignalTextSize = self.noSignalTextNode.updateLayout(videoBounds.insetBy(dx: 12.0, dy: 12.0).size)
        let noSignalTextOrigin = CGPoint(x: (size.width - noSignalTextSize.width) / 2, y: (size.height - noSignalTextSize.height) / 2)
        transition.updateFrameAdditiveToCenter(node: self.noSignalTextNode, frame: CGRect(origin: noSignalTextOrigin, size: noSignalTextSize))
        
        if let videoNode = self.groupVideoNode {
            videoNode.updateLayout(size: size, layoutMode: .fit, transition: transition)
            transition.updateFrame(node: videoNode, frame: videoBounds)
        }
        
        if let glowView = self.videoGlowView {
            let glowViewFrame = videoBounds.insetBy(dx: -Constants.glowVideoInset, dy: -Constants.glowVideoInset)
            transition.updateFrame(view: glowView, frame: glowViewFrame)
        }
        
        let glowPath = UIBezierPath(roundedRect: videoBounds, cornerRadius: Constants.cornerRadius).cgPath
        self.videoGlowMask.shadowPath = glowPath
        transition.updatePath(layer: self.videoGlowMask, path: glowPath)
        transition.updateFrame(layer: self.videoGlowMask, frame: videoBounds)
    }
    
    private func updateVideoReady(_ ready: Bool) {
        guard self.videoReady != ready else { return }
        
        self.videoReady = ready
        self.onVideoReadyChanged?(ready)
        self.fullscreenOverlayNode.isLivestreamActive = ready
        
        DispatchQueue.main.async { [weak self] in
            let duration = 0.3
            let timingFunction = CAMediaTimingFunctionName.easeInEaseOut.rawValue
            
            if ready {
                self?.shimmeringNode?.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration, removeOnCompletion: false, completion: { [weak self] _ in
                    self?.shimmeringNode?.isHidden = true
                })
                self?.videoGlowMask.animate(from: NSNumber(value: Float(0.0)), to: NSNumber(value: Float(Constants.glowOpacity)), keyPath: "shadowOpacity", timingFunction: timingFunction, duration: duration, removeOnCompletion: false)
            } else {
                self?.storeLastFrameThumbnail()
                
                self?.shimmeringNode?.isHidden = false
                self?.shimmeringNode?.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration, removeOnCompletion: false)
                self?.videoGlowMask.animate(from: NSNumber(value: Float(Constants.glowOpacity)), to: NSNumber(value: Float(0.0)), keyPath: "shadowOpacity", timingFunction: timingFunction, duration: duration, removeOnCompletion: false)
            }
        }
    }
    
    private func updateNoSignalMessageVisible(_ visible: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let noSignalTextNode = self?.noSignalTextNode else { return }
            let transition = ContainedViewLayoutTransition.animated(duration: 0.3, curve: .easeInOut)
            transition.updateAlpha(node: noSignalTextNode, alpha: visible ? 1.0 : 0.0)
        }
    }
    
    // MARK: Picture in Picture
    
    private var pictureInPictureController: AVPictureInPictureController?
    
    func startPictureInPicture() {
        self.pictureInPictureController?.startPictureInPicture()
    }
    
    func stopPictureInPicture() {
        self.pictureInPictureController?.stopPictureInPicture()
    }
    
    func updateVideoViewIsEnabledForPictureInPicture() {
        guard let pictureInPictureController = self.pictureInPictureController,
              pictureInPictureController.isPictureInPictureActive
        else {
            self.videoView?.updateIsEnabled(self.visibility)
            return
        }
        
        self.videoView?.updateIsEnabled(true)
    }
    
    private func setupPictureInPicture(delegate: AVPictureInPictureControllerDelegate? = nil) {
        guard let sampleBufferVideoView = self.videoView as? SampleBufferVideoRenderingView else { return }
        
        if #available(iOS 13.0, *) {
            sampleBufferVideoView.sampleBufferLayer.preventsDisplaySleepDuringVideoPlayback = true
        }
        
        if #available(iOSApplicationExtension 15.0, iOS 15.0, *), AVPictureInPictureController.isPictureInPictureSupported() {
            final class PlaybackDelegateImpl: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate {
                func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
                }
                
                func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
                    return CMTimeRange(start: .zero, duration: .positiveInfinity)
                }
                
                func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
                    return false
                }
                
                func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
                }
                
                func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
                    completionHandler()
                }
                
                public func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
                    return false
                }
            }
            
            let contentSource = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: sampleBufferVideoView.sampleBufferLayer, playbackDelegate: PlaybackDelegateImpl())
            let pictureInPictureController = AVPictureInPictureController(contentSource: contentSource)
            
            pictureInPictureController.canStartPictureInPictureAutomaticallyFromInline = true
            pictureInPictureController.requiresLinearPlayback = true
            pictureInPictureController.delegate = delegate
            
            self.pictureInPictureController = pictureInPictureController
        }
    }
    
    // MARK: Thumbnail Caching
    
    private var cachedThumbnailPath: String {
        let resourceId: String
        if let call = self.call.initialCall {
            resourceId = "live-stream_\(call.id)_\(call.accessHash)"
        } else {
            resourceId = "live-stream_\(self.call.internalId)"
        }
        let representationId = "live-stream-frame"
        let mediaBox = self.call.account.postbox.mediaBox
        return mediaBox.cachedRepresentationPathForId(resourceId, representationId: representationId, keepDuration: .shortLived)
    }
    
    private func storeLastFrameThumbnail() {
        guard let pixelBuffer = self.videoView?.getLastFramePixelBuffer() else { return }
        
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        
        guard var dataImage = cgImage else { return }
        let imageSize = CGSize(width: dataImage.width, height: dataImage.height)
        
        let image = generateImage(imageSize, contextGenerator: { size, context -> Void in
            let imageContextSize = size.width > 200.0 ? CGSize(width: 192.0, height: 192.0) : CGSize(width: 64.0, height: 64.0)
            if let imageContext = DrawingContext(size: imageContextSize, scale: 1.0, clear: true) {
                imageContext.withFlippedContext { c in
                    c.draw(dataImage, in: CGRect(origin: .zero, size: imageContextSize))
                    
                    context.setBlendMode(.saturation)
                    context.setFillColor(UIColor(rgb: 0xffffff, alpha: 1.0).cgColor)
                    context.fill(CGRect(origin: .zero, size: size))
                    context.setBlendMode(.copy)
                }
                
                let iterationsCount = size.width > 200.0 ? 5 : 1
                for _ in 0...iterationsCount {
                    telegramFastBlurMore(Int32(imageContext.size.width * imageContext.scale),
                                         Int32(imageContext.size.height * imageContext.scale),
                                         Int32(imageContext.bytesPerRow), imageContext.bytes)
                }
                
                dataImage = imageContext.generateImage()!.cgImage!
            }
            
            context.draw(dataImage, in: CGRect(origin: .zero, size: imageSize))
        })
        
        self.shimmeringNode?.thumbnailImage = image
        try? image?.pngData()?.write(to: URL(fileURLWithPath: self.cachedThumbnailPath))
    }
    
    // MARK: Fullscreen UI
    
    private(set) lazy var fullscreenOverlayNode = StreamVideoOverlayNode(strings: self.strings, context: self.call.accountContext)
    private var scheduledDismissUITimer: SwiftSignalKit.Timer?
    private var isFullscreen: Bool = false {
        didSet {
            if !self.isFullscreen {
                self.displayUI = false
            }
        }
    }
    private var displayUI: Bool = false {
        didSet {
            guard oldValue != self.displayUI else { return }
            if self.displayUI {
                self.scheduleDismissUI()
            } else {
                self.scheduledDismissUITimer = nil
            }
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                let transition = ContainedViewLayoutTransition.animated(duration: 0.4, curve: .easeInOut)
                transition.updateAlpha(node: strongSelf.fullscreenOverlayNode, alpha: strongSelf.displayUI ? 1.0 : 0.0)
            }
        }
    }
    
    private func scheduleDismissUI() {
        guard self.scheduledDismissUITimer == nil else { return }
        self.scheduledDismissUITimer = SwiftSignalKit.Timer(timeout: 3.0, repeat: false, completion: { [weak self] in
            self?.scheduledDismissUITimer = nil
            self?.displayUI = false
        }, queue: .mainQueue())
        self.scheduledDismissUITimer?.start()
    }
}

// MARK: - Fullscreen Overlay Node

final class StreamVideoOverlayNode: ASDisplayNode {
    
    var title: String = ""
    var canManageCall: Bool = false {
        didSet {
            self.optionsButton.isHidden = !self.canManageCall
        }
    }
    
    var onShareButtonPressed: (() -> Void)?
    var onMinimizeButtonPressed: (() -> Void)?
    var optionsButtonContextAction: ((ContextReferenceContentNode, ContextGesture?) -> Void)?
    
    var isRecording: Bool {
        get { self.titleNode.isRecording }
        set { self.titleNode.isRecording = newValue }
    }
    
    var isLivestreamActive: Bool {
        get { self.titleNode.isLivestreamActive }
        set { self.titleNode.isLivestreamActive = newValue }
    }
    
    private let strings: PresentationStrings
    
    private let navigationBar = ASDisplayNode()
    private let toolbar = ASDisplayNode()
    
    private let titleNode = VoiceChatTitleNode()
    private let optionsButton: VoiceChatHeaderButton
    private let participantsNode = ImmediateAnimatedCountLabelNode()
    private let shareButton = HighlightableButtonNode()
    private let minimizeButton = HighlightableButtonNode()
    
    fileprivate init(strings: PresentationStrings, context: AccountContext) {
        self.strings = strings
        self.optionsButton = VoiceChatHeaderButton(context: context)
        super.init()
        
        self.navigationBar.view.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
        self.toolbar.view.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
        
        self.optionsButton.isHidden = true
        self.optionsButton.setContent(.more(optionsOutlinedImage()))
        self.optionsButton.addTarget(self, action: #selector(self.optionsPressed), forControlEvents: .touchUpInside)
        self.optionsButton.contextAction = { [weak self] _, gesture in
            if let referenceNode = self?.optionsButton.referenceNode {
                self?.optionsButtonContextAction?(referenceNode, gesture)
            }
        }
        
        let shareImage = generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Accessory Panels/MessageSelectionForward"), color: .white)
        self.shareButton.setImage(shareImage, for: .normal)
        self.shareButton.addTarget(self, action: #selector(self.sharePressed), forControlEvents: .touchUpInside)
        
        let minimizeImage = generateTintedImage(image: UIImage(bundleImageName: "Media Gallery/Minimize"), color: .white)
        self.minimizeButton.setImage(minimizeImage, for: .normal)
        self.minimizeButton.addTarget(self, action: #selector(self.minimizePressed), forControlEvents: .touchUpInside)
        
        self.addSubnode(self.navigationBar)
        self.addSubnode(self.toolbar)
        
        self.navigationBar.addSubnode(self.titleNode)
        self.navigationBar.addSubnode(self.optionsButton)
        
        self.toolbar.addSubnode(self.participantsNode)
        self.toolbar.addSubnode(self.shareButton)
        self.toolbar.addSubnode(self.minimizeButton)
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self.view ? nil : view
    }
    
    fileprivate func update(size: CGSize, safeInsets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        let navigationBarSize = CGSize(width: size.width, height: safeInsets.top + Constants.fullscreenBarHeight)
        transition.updateFrame(node: self.navigationBar, frame: CGRect(origin: .zero, size: navigationBarSize))
        
        let titleSize = CGSize(width: navigationBarSize.width - safeInsets.left - safeInsets.right - 8.0, height: Constants.fullscreenBarHeight)
        let titleOrigin = CGPoint(x: (navigationBarSize.width - titleSize.width) / 2, y: navigationBarSize.height - titleSize.height)
        self.titleNode.update(size: titleSize, title: self.title)
        transition.updateFrame(node: self.titleNode, frame: CGRect(origin: titleOrigin, size: titleSize))
        
        let optionsButtonSize = CGSize(width: 28.0, height: 28.0)
        let optionsButtonOrigin = CGPoint(x: navigationBarSize.width - safeInsets.right - 4.0 - optionsButtonSize.width - (Constants.fullscreenBarHeight - optionsButtonSize.width) / 2, y: safeInsets.top + (Constants.fullscreenBarHeight - optionsButtonSize.height) / 2)
        transition.updateFrame(node: self.optionsButton, frame: CGRect(origin: optionsButtonOrigin, size: optionsButtonSize))
        
        let toolbarSize = CGSize(width: size.width, height: safeInsets.bottom + Constants.fullscreenBarHeight)
        let toolbarFrame = CGRect(origin: CGPoint(x: 0.0, y: size.height - toolbarSize.height), size: toolbarSize)
        transition.updateFrame(node: self.toolbar, frame: toolbarFrame)
        
        let textSize = self.participantsNode.updateLayout(size: CGSize(width: toolbarFrame.inset(by: safeInsets).width - 96.0, height: Constants.fullscreenBarHeight), animated: true)
        let textOrigin = CGPoint(x: (toolbarFrame.width - textSize.width) / 2, y: (Constants.fullscreenBarHeight - textSize.height) / 2)
        transition.updateFrame(node: self.participantsNode, frame: CGRect(origin: textOrigin, size: textSize))
        
        let shareFrame = CGRect(x: toolbarFrame.minX + safeInsets.left + 4.0, y: 0.0, width: Constants.fullscreenBarHeight, height: Constants.fullscreenBarHeight)
        transition.updateFrame(node: self.shareButton, frame: shareFrame)
        
        let minimizeFrame = CGRect(x: toolbarFrame.maxX - safeInsets.right - 4.0 - Constants.fullscreenBarHeight, y: 0.0, width: Constants.fullscreenBarHeight, height: Constants.fullscreenBarHeight)
        transition.updateFrame(node: self.minimizeButton, frame: minimizeFrame)
    }
    
    func update(participantCount: Int32) {
        let participantsString = participantCount == 0 ? self.strings.LiveStream_NoViewers : self.strings.LiveStream_ViewerCount(participantCount)
        let makeAttributedString = { (string: String) in NSAttributedString(string: string, font: .systemFont(ofSize: 17.0), textColor: .white) }
        
        var segments = [AnimatedCountLabelNode.Segment]()
        var accumulatedString = ""
        var index = 0
        
        for char in participantsString {
            if let value = char.wholeNumberValue {
                if !accumulatedString.isEmpty {
                    segments.append(.text(index, makeAttributedString(accumulatedString)))
                    accumulatedString = ""
                    index += 1
                }
                
                segments.append(.number(value, makeAttributedString(String(char))))
            } else {
                accumulatedString.append(char)
            }
        }
        
        if !accumulatedString.isEmpty {
            segments.append(.text(index, makeAttributedString(accumulatedString)))
        }
        
        self.participantsNode.segments = segments
    }
    
    @objc private func sharePressed() {
        self.onShareButtonPressed?()
    }
    
    @objc private func minimizePressed() {
        self.onMinimizeButtonPressed?()
    }
    
    @objc private func optionsPressed() {
        self.optionsButton.play()
        self.optionsButton.contextAction?(self.optionsButton.containerNode, nil)
    }
}

// MARK: - Shimmering Node

private final class StreamShimmeringNode: ASDisplayNode {
    
    var thumbnailImage: UIImage? {
        get { self.backgroundNode.image }
        set { self.backgroundNode.setSignal(.single(newValue)) }
    }
    
    private let backgroundNode: ImageNode
    private let effectNode: ShimmerEffectForegroundNode
    
    private let borderNode: ASDisplayNode
    private var borderMaskView: UIView?
    private let borderEffectNode: ShimmerEffectForegroundNode
    
    private var currentShimmeringColor: UIColor?
    private var currentShimmering: Bool?
    private var currentSize: CGSize?
    
    public init(account: Account, peer: Peer, image: UIImage?) {
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
        
        if let thumbnailImage = image {
            self.thumbnailImage = thumbnailImage
        } else {
            self.backgroundNode.setSignal(peerAvatarCompleteImage(account: account, peer: EnginePeer(peer), size: CGSize(width: 250.0, height: 250.0), round: false, font: Font.regular(16.0), drawLetters: false, fullSize: false, blurred: true))
        }
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
