import Foundation
import UIKit
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import TelegramAudio
import AccountContext
import LocalizedPeerData
import CallsEmoji
import TooltipUI
import AlertUI
import PresentationDataUtils
import DeviceAccess
import ContextUI
import GradientBackground

private func interpolateFrame(from fromValue: CGRect, to toValue: CGRect, t: CGFloat) -> CGRect {
    return CGRect(x: floorToScreenPixels(toValue.origin.x * t + fromValue.origin.x * (1.0 - t)), y: floorToScreenPixels(toValue.origin.y * t + fromValue.origin.y * (1.0 - t)), width: floorToScreenPixels(toValue.size.width * t + fromValue.size.width * (1.0 - t)), height: floorToScreenPixels(toValue.size.height * t + fromValue.size.height * (1.0 - t)))
}

private func interpolate(from: CGFloat, to: CGFloat, value: CGFloat) -> CGFloat {
    return (1.0 - value) * from + value * to
}

private final class CallVideoNode: ASDisplayNode, PreviewVideoNode {
    private let videoTransformContainer: ASDisplayNode
    private let videoView: PresentationCallVideoView
    
    private var effectView: UIVisualEffectView?
    private let videoPausedNode: ImmediateTextNode
    
    private var isBlurred: Bool = false
    private var currentCornerRadius: CGFloat = 0.0
    
    private let isReadyUpdated: () -> Void
    private(set) var isReady: Bool = false
    private var isReadyTimer: SwiftSignalKit.Timer?
    
    private let readyPromise = ValuePromise(false)
    var ready: Signal<Bool, NoError> {
        return self.readyPromise.get()
    }
    
    private let isFlippedUpdated: (CallVideoNode) -> Void
    
    private(set) var currentOrientation: PresentationCallVideoView.Orientation
    private(set) var currentAspect: CGFloat = 0.0
    
    private var previousVideoHeight: CGFloat?
    
    init(videoView: PresentationCallVideoView, disabledText: String?, assumeReadyAfterTimeout: Bool, isReadyUpdated: @escaping () -> Void, orientationUpdated: @escaping () -> Void, isFlippedUpdated: @escaping (CallVideoNode) -> Void) {
        self.isReadyUpdated = isReadyUpdated
        self.isFlippedUpdated = isFlippedUpdated
        
        self.videoTransformContainer = ASDisplayNode()
        self.videoView = videoView
        videoView.view.clipsToBounds = true
        videoView.view.backgroundColor = .black
        
        self.currentOrientation = videoView.getOrientation()
        self.currentAspect = videoView.getAspect()
        
        self.videoPausedNode = ImmediateTextNode()
        self.videoPausedNode.alpha = 0.0
        self.videoPausedNode.maximumNumberOfLines = 3
        
        super.init()
        
        self.backgroundColor = .black
        self.clipsToBounds = true
        
        if #available(iOS 13.0, *) {
            self.layer.cornerCurve = .continuous
        }
        
        self.videoTransformContainer.view.addSubview(self.videoView.view)
        self.addSubnode(self.videoTransformContainer)
        
        if let disabledText = disabledText {
            self.videoPausedNode.attributedText = NSAttributedString(string: disabledText, font: Font.regular(17.0), textColor: .white)
            self.addSubnode(self.videoPausedNode)
        }
        
        self.videoView.setOnFirstFrameReceived { [weak self] aspectRatio in
            Queue.mainQueue().async {
                guard let strongSelf = self else {
                    return
                }
                if !strongSelf.isReady {
                    strongSelf.isReady = true
                    strongSelf.readyPromise.set(true)
                    strongSelf.isReadyTimer?.invalidate()
                    strongSelf.isReadyUpdated()
                }
            }
        }
        
        self.videoView.setOnOrientationUpdated { [weak self] orientation, aspect in
            Queue.mainQueue().async {
                guard let strongSelf = self else {
                    return
                }
                if strongSelf.currentOrientation != orientation || strongSelf.currentAspect != aspect {
                    strongSelf.currentOrientation = orientation
                    strongSelf.currentAspect = aspect
                    orientationUpdated()
                }
            }
        }
        
        self.videoView.setOnIsMirroredUpdated { [weak self] _ in
            Queue.mainQueue().async {
                guard let strongSelf = self else {
                    return
                }
                strongSelf.isFlippedUpdated(strongSelf)
            }
        }
        
        if assumeReadyAfterTimeout {
            self.isReadyTimer = SwiftSignalKit.Timer(timeout: 3.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                if !strongSelf.isReady {
                    strongSelf.isReady = true
                    strongSelf.readyPromise.set(true)
                    strongSelf.isReadyUpdated()
                }
            }, queue: .mainQueue())
        }
        self.isReadyTimer?.start()
    }
    
    deinit {
        self.isReadyTimer?.invalidate()
    }
    
    override func didLoad() {
        super.didLoad()
        
        if #available(iOS 13.0, *) {
            self.layer.cornerCurve = .continuous
        }
    }
    
    func animateRadialMask(from fromRect: CGRect, to toRect: CGRect) {
        let maskLayer = CAShapeLayer()
        maskLayer.frame = fromRect
        
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(origin: CGPoint(), size: fromRect.size))
        maskLayer.path = path
        
        self.layer.mask = maskLayer
        
        let topLeft = CGPoint(x: 0.0, y: 0.0)
        let topRight = CGPoint(x: self.bounds.width, y: 0.0)
        let bottomLeft = CGPoint(x: 0.0, y: self.bounds.height)
        let bottomRight = CGPoint(x: self.bounds.width, y: self.bounds.height)
        
        func distance(_ v1: CGPoint, _ v2: CGPoint) -> CGFloat {
            let dx = v1.x - v2.x
            let dy = v1.y - v2.y
            return sqrt(dx * dx + dy * dy)
        }
        
        var maxRadius = distance(toRect.center, topLeft)
        maxRadius = max(maxRadius, distance(toRect.center, topRight))
        maxRadius = max(maxRadius, distance(toRect.center, bottomLeft))
        maxRadius = max(maxRadius, distance(toRect.center, bottomRight))
        maxRadius = ceil(maxRadius)
        
        let targetFrame = CGRect(origin: CGPoint(x: toRect.center.x - maxRadius, y: toRect.center.y - maxRadius), size: CGSize(width: maxRadius * 2.0, height: maxRadius * 2.0))
        
        let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)
        transition.updatePosition(layer: maskLayer, position: targetFrame.center)
        transition.updateTransformScale(layer: maskLayer, scale: maxRadius * 2.0 / fromRect.width, completion: { [weak self] _ in
            self?.layer.mask = nil
        })
    }
    
    func updateLayout(size: CGSize, layoutMode: VideoNodeLayoutMode, transition: ContainedViewLayoutTransition) {
        self.updateLayout(size: size, cornerRadius: self.currentCornerRadius, isOutgoing: true, deviceOrientation: .portrait, isCompactLayout: false, transition: transition)
    }
    
    func updateLayout(size: CGSize, cornerRadius: CGFloat, isOutgoing: Bool, deviceOrientation: UIDeviceOrientation, isCompactLayout: Bool, transition: ContainedViewLayoutTransition) {
        self.currentCornerRadius = cornerRadius
        
        var rotationAngle: CGFloat
        if false && isOutgoing && isCompactLayout {
            rotationAngle = CGFloat.pi / 2.0
        } else {
            switch self.currentOrientation {
            case .rotation0:
                rotationAngle = 0.0
            case .rotation90:
                rotationAngle = CGFloat.pi / 2.0
            case .rotation180:
                rotationAngle = CGFloat.pi
            case .rotation270:
                rotationAngle = -CGFloat.pi / 2.0
            }
            
            var additionalAngle: CGFloat = 0.0
            switch deviceOrientation {
            case .portrait:
                additionalAngle = 0.0
            case .landscapeLeft:
                additionalAngle = CGFloat.pi / 2.0
            case .landscapeRight:
                additionalAngle = -CGFloat.pi / 2.0
            case .portraitUpsideDown:
                rotationAngle = CGFloat.pi
            default:
                additionalAngle = 0.0
            }
            rotationAngle += additionalAngle
            if abs(rotationAngle - CGFloat.pi * 3.0 / 2.0) < 0.01 {
                rotationAngle = -CGFloat.pi / 2.0
            }
            if abs(rotationAngle - (-CGFloat.pi)) < 0.01 {
                rotationAngle = -CGFloat.pi + 0.001
            }
        }
        
        let rotateFrame = abs(rotationAngle.remainder(dividingBy: CGFloat.pi)) > 1.0
        let fittingSize: CGSize
        if rotateFrame {
            fittingSize = CGSize(width: size.height, height: size.width)
        } else {
            fittingSize = size
        }
        
        let unboundVideoSize = CGSize(width: self.currentAspect * 10000.0, height: 10000.0)
        
        var fittedVideoSize = unboundVideoSize.fitted(fittingSize)
        if fittedVideoSize.width < fittingSize.width || fittedVideoSize.height < fittingSize.height {
            let isVideoPortrait = unboundVideoSize.width < unboundVideoSize.height
            let isFittingSizePortrait = fittingSize.width < fittingSize.height
            
            if isCompactLayout && isVideoPortrait == isFittingSizePortrait {
                fittedVideoSize = unboundVideoSize.aspectFilled(fittingSize)
            } else {
                let maxFittingEdgeDistance: CGFloat
                if isCompactLayout {
                    maxFittingEdgeDistance = 200.0
                } else {
                    maxFittingEdgeDistance = 400.0
                }
                if fittedVideoSize.width > fittingSize.width - maxFittingEdgeDistance && fittedVideoSize.height > fittingSize.height - maxFittingEdgeDistance {
                    fittedVideoSize = unboundVideoSize.aspectFilled(fittingSize)
                }
            }
        }
        
        let rotatedVideoHeight: CGFloat = max(fittedVideoSize.height, fittedVideoSize.width)
        
        let videoFrame: CGRect = CGRect(origin: CGPoint(), size: fittedVideoSize)
        
        let videoPausedSize = self.videoPausedNode.updateLayout(CGSize(width: size.width - 16.0, height: 100.0))
        transition.updateFrame(node: self.videoPausedNode, frame: CGRect(origin: CGPoint(x: floor((size.width - videoPausedSize.width) / 2.0), y: floor((size.height - videoPausedSize.height) / 2.0)), size: videoPausedSize))
        
        self.videoTransformContainer.bounds = CGRect(origin: CGPoint(), size: videoFrame.size)
        if transition.isAnimated && !videoFrame.height.isZero, let previousVideoHeight = self.previousVideoHeight, !previousVideoHeight.isZero {
            let scaleDifference = previousVideoHeight / rotatedVideoHeight
            if abs(scaleDifference - 1.0) > 0.001 {
                transition.animateTransformScale(node: self.videoTransformContainer, from: scaleDifference, additive: true)
            }
        }
        self.previousVideoHeight = rotatedVideoHeight
        transition.updatePosition(node: self.videoTransformContainer, position: CGPoint(x: size.width / 2.0, y: size.height / 2.0))
        transition.updateTransformRotation(view: self.videoTransformContainer.view, angle: rotationAngle)
        
        let localVideoFrame = CGRect(origin: CGPoint(), size: videoFrame.size)
        self.videoView.view.bounds = localVideoFrame
        self.videoView.view.center = localVideoFrame.center
        // TODO: properly fix the issue
        // On iOS 13 and later metal layer transformation is broken if the layer does not require compositing
        self.videoView.view.alpha = 0.995
        
        if let effectView = self.effectView {
            transition.updateFrame(view: effectView, frame: localVideoFrame)
        }
        
        transition.updateCornerRadius(layer: self.layer, cornerRadius: self.currentCornerRadius)
    }
    
    func updateIsBlurred(isBlurred: Bool, light: Bool = false, animated: Bool = true) {
        if self.hasScheduledUnblur {
            self.hasScheduledUnblur = false
        }
        if self.isBlurred == isBlurred {
            return
        }
        self.isBlurred = isBlurred
        
        if isBlurred {
            if self.effectView == nil {
                let effectView = UIVisualEffectView()
                self.effectView = effectView
                effectView.frame = self.videoTransformContainer.bounds
                self.videoTransformContainer.view.addSubview(effectView)
            }
            if animated {
                UIView.animate(withDuration: 0.3, animations: {
                    self.videoPausedNode.alpha = 1.0
                    self.effectView?.effect = UIBlurEffect(style: light ? .light : .dark)
                })
            } else {
                self.effectView?.effect = UIBlurEffect(style: light ? .light : .dark)
            }
        } else if let effectView = self.effectView {
            self.effectView = nil
            UIView.animate(withDuration: 0.3, animations: {
                self.videoPausedNode.alpha = 0.0
                effectView.effect = nil
            }, completion: { [weak effectView] _ in
                effectView?.removeFromSuperview()
            })
        }
    }
    
    private var hasScheduledUnblur = false
    func flip(withBackground: Bool) {
        if withBackground {
            self.backgroundColor = .black
        }
        UIView.transition(with: withBackground ? self.videoTransformContainer.view : self.view, duration: 0.4, options: [.transitionFlipFromLeft, .curveEaseOut], animations: {
            UIView.performWithoutAnimation {
                self.updateIsBlurred(isBlurred: true, light: false, animated: false)
            }
        }) { finished in
            self.backgroundColor = nil
            self.hasScheduledUnblur = true
            Queue.mainQueue().after(0.5) {
                if self.hasScheduledUnblur {
                    self.updateIsBlurred(isBlurred: false)
                }
            }
        }
    }
}

final class CallControllerNode: ViewControllerTracingNode, CallControllerNodeProtocol {
    private enum VideoNodeCorner {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }
    
    private enum BackgroundGradient {
        case blueViolet
        case blueGreen
        case orangeRed
        
        var colors: [UIColor] {
            let hexCodes: [UInt32]
            switch self {
            case .blueViolet:
                hexCodes = [0xAC65D4, 0x7261DA, 0x5295D6, 0x616AD5]
            case .blueGreen:
                hexCodes = [0x53A6DE, 0x398D6F, 0xBAC05D, 0x3C9C8F]
            case .orangeRed:
                hexCodes = [0xC94986, 0xFF7E46, 0xB84498, 0xF4992E]
            }
            return hexCodes.map(UIColor.init(rgb:))
        }
    }
    
    private let sharedContext: SharedAccountContext
    private let account: Account
    
    private let statusBar: StatusBar
    
    private var presentationData: PresentationData
    private var peer: Peer?
    private let debugInfo: Signal<(String, String), NoError>
    private var forceReportRating = false
    private let easyDebugAccess: Bool
    private let call: PresentationCall
    
    private let containerTransformationNode: ASDisplayNode
    private let containerNode: ASDisplayNode
    private let videoContainerNode: PinchSourceContainerNode
    
    private let avatarNode: CallControllerAvatarNode
    private let dimNode: ASImageNode
    private let backgroundNode: GradientBackgroundNode
    private var backgroundAnimationTimer: SwiftSignalKit.Timer?
    private var currentBackground: BackgroundGradient = .blueViolet
    
    private var candidateIncomingVideoNodeValue: CallVideoNode?
    private var incomingVideoNodeValue: CallVideoNode?
    private var incomingVideoViewRequested: Bool = false
    private var candidateOutgoingVideoNodeValue: CallVideoNode?
    private var outgoingVideoNodeValue: CallVideoNode?
    private var outgoingVideoViewRequested: Bool = false
    
    private var removedMinimizedVideoNodeValue: CallVideoNode?
    private var removedExpandedVideoNodeValue: CallVideoNode?
    
    private var isRequestingVideo: Bool = false
    private var animateRequestedVideoOnce: Bool = false
    
    private var hiddenUIForActiveVideoCallOnce: Bool = false
    private var hideUIForActiveVideoCallTimer: SwiftSignalKit.Timer?
        
    private var expandedVideoNode: CallVideoNode?
    private var minimizedVideoNode: CallVideoNode?
    private var disableAnimationForExpandedVideoOnce: Bool = false
    private var animationForExpandedVideoSnapshotView: UIView? = nil
    
    private var outgoingVideoNodeCorner: VideoNodeCorner = .bottomRight
    private let backButtonArrowNode: ASImageNode
    private let backButtonNode: HighlightableButtonNode
    private let statusNode: CallControllerStatusNode
    private let toastNode: CallControllerToastContainerNode
    private let weakNetworkToastNode: CallControllerToastItemNode
    private let buttonsNode: CallControllerButtonsNode
    private let ratingNode: CallControllerRatingNode
    private let closeButtonNode: CallControllerCloseButtonNode
    
    private let keyPreviewNode: CallControllerKeyPreviewNode
    private let keyPreviewNodeSize = CGSize(width: 304.0, height: 225.0)
    
    private var debugNode: CallDebugNode?
    
    private var keyTextData: (Data, String)?
    private let keyButtonNode: CallControllerKeyButton
    
    private var validLayout: (ContainerViewLayout, CGFloat)?
    private var disableActionsUntilTimestamp: Double = 0.0
    
    private var displayedVersionOutdatedAlert: Bool = false
    
    var isMuted: Bool = false {
        didSet {
            self.buttonsNode.isMuted = self.isMuted
            self.updateToastContent()
            if let (layout, navigationBarHeight) = self.validLayout {
                self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
            }
        }
    }
    
    private var shouldStayHiddenUntilConnection: Bool = false
    
    private var audioOutputState: ([AudioSessionOutput], currentOutput: AudioSessionOutput?)?
    private var callState: PresentationCallState?
    
    var toggleMute: (() -> Void)?
    var setCurrentAudioOutput: ((AudioSessionOutput) -> Void)?
    var beginAudioOuputSelection: ((Bool) -> Void)?
    var acceptCall: (() -> Void)?
    var endCall: (() -> Void)?
    var back: (() -> Void)?
    var presentCallRating: ((CallId, Bool) -> Void)?
    var sendCallRating: ((CallId, Bool, Int) -> Void)?
    var callEnded: ((Bool) -> Void)?
    var dismissedInteractively: (() -> Void)?
    var present: ((ViewController) -> Void)?
    var dismissAllTooltips: (() -> Void)?
    
    private var toastContent: CallControllerToastContent?
    private var displayToastsAfterTimestamp: Double?
    
    private var buttonsMode: CallControllerButtonsMode?
    
    private var isUIHidden: Bool = false
    private var isVideoPaused: Bool = false
    private var isVideoPinched: Bool = false
    
    private enum PictureInPictureGestureState {
        case none
        case collapsing(didSelectCorner: Bool)
        case dragging(initialPosition: CGPoint, draggingPosition: CGPoint)
    }
    
    private var pictureInPictureGestureState: PictureInPictureGestureState = .none
    private var pictureInPictureCorner: VideoNodeCorner = .topRight
    private var pictureInPictureTransitionFraction: CGFloat = 0.0
    
    private var deviceOrientation: UIDeviceOrientation = .portrait
    private var orientationDidChangeObserver: NSObjectProtocol?
    
    private var currentRequestedAspect: CGFloat?
    
    private var currentCallTimestamp: Double?
    
    init(sharedContext: SharedAccountContext, account: Account, presentationData: PresentationData, statusBar: StatusBar, debugInfo: Signal<(String, String), NoError>, shouldStayHiddenUntilConnection: Bool = false, easyDebugAccess: Bool, call: PresentationCall) {
        self.sharedContext = sharedContext
        self.account = account
        self.presentationData = presentationData
        self.statusBar = statusBar
        self.debugInfo = debugInfo
        self.shouldStayHiddenUntilConnection = shouldStayHiddenUntilConnection
        self.easyDebugAccess = easyDebugAccess
        self.call = call
        
        self.containerTransformationNode = ASDisplayNode()
        self.containerTransformationNode.clipsToBounds = true
        
        self.containerNode = ASDisplayNode()
        
        self.videoContainerNode = PinchSourceContainerNode()
        
        self.avatarNode = CallControllerAvatarNode(sharedContext: sharedContext, account: account, presentationData: presentationData, call: call)
        self.backgroundNode = GradientBackgroundNode(colors: self.currentBackground.colors, adjustSaturation: false)
        self.dimNode = ASImageNode()
        self.dimNode.contentMode = .scaleToFill
        self.dimNode.isUserInteractionEnabled = false
        self.dimNode.backgroundColor = UIColor(white: 0.0, alpha: 0.3)
        
        self.backButtonArrowNode = ASImageNode()
        self.backButtonArrowNode.isHidden = true
        self.backButtonArrowNode.displayWithoutProcessing = true
        self.backButtonArrowNode.displaysAsynchronously = false
        self.backButtonArrowNode.image = NavigationBarTheme.generateBackArrowImage(color: .white)
        self.backButtonNode = HighlightableButtonNode()
        self.backButtonNode.isHidden = true
        
        self.statusNode = CallControllerStatusNode()
        
        self.buttonsNode = CallControllerButtonsNode(strings: self.presentationData.strings)
        self.toastNode = CallControllerToastContainerNode(strings: self.presentationData.strings)
        
        self.weakNetworkToastNode = CallControllerToastItemNode()
        self.weakNetworkToastNode.isHidden = true
        
        self.keyButtonNode = CallControllerKeyButton(accountContext: self.call.context)
        self.keyButtonNode.isHidden = true
        self.keyButtonNode.accessibilityElementsHidden = false
        
        self.keyPreviewNode = CallControllerKeyPreviewNode(accountContext: self.call.context)
        self.keyPreviewNode.isHidden = true
        
        self.ratingNode = CallControllerRatingNode(strings: self.presentationData.strings)
        self.ratingNode.isHidden = true
        
        self.closeButtonNode = CallControllerCloseButtonNode(strings: self.presentationData.strings)
        self.closeButtonNode.isHidden = true
        
        super.init()
        
        self.containerNode.backgroundColor = .black
        
        self.addSubnode(self.containerTransformationNode)
        self.containerTransformationNode.addSubnode(self.containerNode)
        
        self.backButtonNode.setTitle(presentationData.strings.Common_Back, with: Font.regular(17.0), with: .white, for: [])
        self.backButtonNode.accessibilityLabel = presentationData.strings.Call_VoiceOver_Minimize
        self.backButtonNode.accessibilityTraits = [.button]
        self.backButtonNode.hitTestSlop = UIEdgeInsets(top: -8.0, left: -20.0, bottom: -8.0, right: -8.0)
        self.backButtonNode.highligthedChanged = { [weak self] highlighted in
            if let strongSelf = self {
                if highlighted {
                    strongSelf.backButtonNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.backButtonArrowNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.backButtonNode.alpha = 0.4
                    strongSelf.backButtonArrowNode.alpha = 0.4
                } else {
                    strongSelf.backButtonNode.alpha = 1.0
                    strongSelf.backButtonArrowNode.alpha = 1.0
                    strongSelf.backButtonNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                    strongSelf.backButtonArrowNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                }
            }
        }
        
        self.containerNode.addSubnode(self.backgroundNode)
        self.containerNode.addSubnode(self.avatarNode)
        self.containerNode.addSubnode(self.videoContainerNode)
        self.containerNode.addSubnode(self.dimNode)
        self.containerNode.addSubnode(self.statusNode)
        self.containerNode.addSubnode(self.keyPreviewNode)
        self.containerNode.addSubnode(self.buttonsNode)
        self.containerNode.addSubnode(self.closeButtonNode)
        self.containerNode.addSubnode(self.toastNode)
        self.containerNode.addSubnode(self.weakNetworkToastNode)
        self.containerNode.addSubnode(self.ratingNode)
        self.containerNode.addSubnode(self.keyButtonNode)
        self.containerNode.addSubnode(self.backButtonArrowNode)
        self.containerNode.addSubnode(self.backButtonNode)
        
        self.buttonsNode.mute = { [weak self] in
            self?.toggleMute?()
            self?.cancelScheduledUIHiding()
        }
        
        self.buttonsNode.speaker = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.beginAudioOuputSelection?(strongSelf.hasVideoNodes)
            strongSelf.cancelScheduledUIHiding()
        }
                
        self.buttonsNode.acceptOrEnd = { [weak self] in
            guard let strongSelf = self, let callState = strongSelf.callState else {
                return
            }
            switch callState.state {
            case .active, .connecting, .reconnecting:
                strongSelf.endCall?()
                strongSelf.cancelScheduledUIHiding()
            case .requesting:
                strongSelf.endCall?()
            case .ringing:
                strongSelf.acceptCall?()
            default:
                break
            }
            strongSelf.dismissKeyPreviewNode()
        }
        
        self.buttonsNode.decline = { [weak self] in
            self?.endCall?()
        }
        
        self.buttonsNode.toggleVideo = { [weak self] in
            guard let strongSelf = self, let callState = strongSelf.callState else {
                return
            }
            switch callState.state {
            case .active:
                var isScreencastActive = false
                switch callState.videoState {
                case .active(true), .paused(true):
                    isScreencastActive = true
                default:
                    break
                }

                if isScreencastActive {
                    (strongSelf.call as! PresentationCallImpl).disableScreencast()
                } else if strongSelf.outgoingVideoNodeValue == nil {
                    DeviceAccess.authorizeAccess(to: .camera(.videoCall), onlyCheck: true, presentationData: strongSelf.presentationData, present: { [weak self] c, a in
                        if let strongSelf = self {
                            strongSelf.present?(c)
                        }
                    }, openSettings: { [weak self] in
                        self?.sharedContext.applicationBindings.openSettings()
                    }, _: { [weak self] ready in
                        guard let strongSelf = self, ready else {
                            return
                        }
                        let proceed = {
                            switch callState.videoState {
                            case .inactive:
                                strongSelf.isRequestingVideo = true
                                strongSelf.updateButtonsMode()
                            default:
                                break
                            }
                            strongSelf.call.requestVideo()
                        }
                        
                        strongSelf.call.makeOutgoingVideoView(completion: { [weak self] outgoingVideoView in
                            guard let strongSelf = self else {
                                return
                            }
                            
                            if let outgoingVideoView = outgoingVideoView {
                                outgoingVideoView.view.backgroundColor = .black
                                outgoingVideoView.view.clipsToBounds = true
                                
                                var updateLayoutImpl: ((ContainerViewLayout, CGFloat) -> Void)?
                                
                                let outgoingVideoNode = CallVideoNode(videoView: outgoingVideoView, disabledText: nil, assumeReadyAfterTimeout: true, isReadyUpdated: {
                                    guard let strongSelf = self, let (layout, navigationBarHeight) = strongSelf.validLayout else {
                                        return
                                    }
                                    updateLayoutImpl?(layout, navigationBarHeight)
                                }, orientationUpdated: {
                                    guard let strongSelf = self, let (layout, navigationBarHeight) = strongSelf.validLayout else {
                                        return
                                    }
                                    updateLayoutImpl?(layout, navigationBarHeight)
                                }, isFlippedUpdated: { _ in
                                    guard let strongSelf = self, let (layout, navigationBarHeight) = strongSelf.validLayout else {
                                        return
                                    }
                                    updateLayoutImpl?(layout, navigationBarHeight)
                                })
                                
                                let controller = VoiceChatCameraPreviewController(sharedContext: strongSelf.sharedContext, cameraNode: outgoingVideoNode, shareCamera: { _, _ in
                                    proceed()
                                }, switchCamera: { [weak self] in
                                    Queue.mainQueue().after(0.1) {
                                        self?.call.switchVideoCamera()
                                    }
                                })
                                strongSelf.present?(controller)
                                
                                updateLayoutImpl = { [weak controller] layout, navigationBarHeight in
                                    controller?.containerLayoutUpdated(layout, transition: .immediate)
                                }
                            }
                        })
                    })
                } else {
                    strongSelf.call.disableVideo()
                    strongSelf.cancelScheduledUIHiding()
                }
            default:
                break
            }
        }
        
        self.buttonsNode.rotateCamera = { [weak self] in
            guard let strongSelf = self, !strongSelf.areUserActionsDisabledNow() else {
                return
            }
            strongSelf.disableActionsUntilTimestamp = CACurrentMediaTime() + 1.0
            if let outgoingVideoNode = strongSelf.outgoingVideoNodeValue {
                outgoingVideoNode.flip(withBackground: outgoingVideoNode !== strongSelf.minimizedVideoNode)
            }
            strongSelf.call.switchVideoCamera()
            if let _ = strongSelf.outgoingVideoNodeValue {
                if let (layout, navigationBarHeight) = strongSelf.validLayout {
                    strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
                }
            }
            strongSelf.cancelScheduledUIHiding()
        }
        
        self.keyButtonNode.addTarget(self, action: #selector(self.keyPressed), forControlEvents: .touchUpInside)
        self.keyPreviewNode.dismiss = { [weak self] in self?.dismissKeyPreviewNode() }
        
        self.backButtonNode.addTarget(self, action: #selector(self.backPressed), forControlEvents: .touchUpInside)
        self.closeButtonNode.addTarget(self, action: #selector(self.closePressed), forControlEvents: .touchUpInside)
        
        if shouldStayHiddenUntilConnection {
            self.containerNode.alpha = 0.0
            Queue.mainQueue().after(3.0, { [weak self] in
                self?.containerNode.alpha = 1.0
                self?.animateIn()
            })
        } else if call.isVideo && call.isOutgoing {
            self.containerNode.alpha = 0.0
            Queue.mainQueue().after(1.0, { [weak self] in
                self?.containerNode.alpha = 1.0
                self?.animateIn()
            })
        }
        
        self.orientationDidChangeObserver = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: nil, using: { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            let deviceOrientation = UIDevice.current.orientation
            if strongSelf.deviceOrientation != deviceOrientation {
                strongSelf.deviceOrientation = deviceOrientation
                if let (layout, navigationBarHeight) = strongSelf.validLayout {
                    strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                }
            }
        })
        
        self.videoContainerNode.activate = { [weak self] sourceNode in
            guard let strongSelf = self else {
                return
            }
            let pinchController = PinchController(sourceNode: sourceNode, getContentAreaInScreenSpace: {
                return UIScreen.main.bounds
            })
            strongSelf.sharedContext.mainWindow?.presentInGlobalOverlay(pinchController)
            strongSelf.isVideoPinched = true
            
            strongSelf.videoContainerNode.contentNode.clipsToBounds = true
            strongSelf.videoContainerNode.backgroundColor = .black
            
            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                strongSelf.videoContainerNode.contentNode.cornerRadius = layout.deviceMetrics.screenCornerRadius
                
                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
            }
        }
        
        self.videoContainerNode.animatedOut = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isVideoPinched = false
            
            strongSelf.videoContainerNode.backgroundColor = .clear
            strongSelf.videoContainerNode.contentNode.cornerRadius = 0.0
            
            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
            }
        }
    }
    
    deinit {
        if let orientationDidChangeObserver = self.orientationDidChangeObserver {
            NotificationCenter.default.removeObserver(orientationDidChangeObserver)
        }
        self.backgroundAnimationTimer?.invalidate()
    }
    
    override func didLoad() {
        super.didLoad()
        
        let panRecognizer = CallPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:)))
        panRecognizer.shouldBegin = { [weak self] _ in
            guard let strongSelf = self else {
                return false
            }
            if strongSelf.areUserActionsDisabledNow() {
                return false
            }
            return true
        }
        self.view.addGestureRecognizer(panRecognizer)
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:)))
        self.view.addGestureRecognizer(tapRecognizer)
        
        self.avatarNode.playConnectingAnimation()
        self.startBackgroundAnimation()
    }
    
    func updatePeer(accountPeer: Peer, peer: Peer, hasOther: Bool) {
        if !arePeersEqual(self.peer, peer) {
            self.peer = peer
            
            self.avatarNode.setPeer(peer)
            self.dimNode.isHidden = true
            
            self.toastNode.title = EnginePeer(peer).compactDisplayTitle
            self.statusNode.title = EnginePeer(peer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)
            self.keyPreviewNode.infoText = self.presentationData.strings.Call_EmojiDescription(EnginePeer(peer).compactDisplayTitle).string.replacingOccurrences(of: "%%", with: "%")
            
            if hasOther {
                self.statusNode.subtitle = self.presentationData.strings.Call_AnsweringWithAccount(EnginePeer(accountPeer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)).string
                
                if let callState = self.callState {
                    self.updateCallState(callState)
                }
            }
            
            if let (layout, navigationBarHeight) = self.validLayout {
                self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
            }
        }
    }
    
    func updateAudioOutputs(availableOutputs: [AudioSessionOutput], currentOutput: AudioSessionOutput?) {
        if self.audioOutputState?.0 != availableOutputs || self.audioOutputState?.1 != currentOutput {
            self.audioOutputState = (availableOutputs, currentOutput)
            self.updateButtonsMode()
            
            self.setupAudioOutputs()
        }
    }
    
    private func setupAudioOutputs() {
        if self.hasVideo || self.candidateOutgoingVideoNodeValue != nil || self.candidateIncomingVideoNodeValue != nil {
            if let audioOutputState = self.audioOutputState, let currentOutput = audioOutputState.currentOutput {
                switch currentOutput {
                case .headphones, .speaker:
                    break
                case let .port(port) where port.type == .bluetooth || port.type == .wired:
                    break
                default:
                    self.setCurrentAudioOutput?(.speaker)
                }
            }
        }
    }
    
    func updateCallState(_ callState: PresentationCallState) {
        self.callState = callState
        
        let statusValue: CallControllerStatusValue
        var statusReception: Int32?
        
        switch callState.remoteVideoState {
        case .active, .paused:
            if !self.incomingVideoViewRequested {
                self.incomingVideoViewRequested = true
                let delayUntilInitialized = true
                self.call.makeIncomingVideoView(completion: { [weak self] incomingVideoView in
                    guard let strongSelf = self else {
                        return
                    }
                    if let incomingVideoView = incomingVideoView {
                        incomingVideoView.view.backgroundColor = .black
                        incomingVideoView.view.clipsToBounds = true
                        
                        let applyNode: () -> Void = {
                            guard let strongSelf = self, let incomingVideoNode = strongSelf.candidateIncomingVideoNodeValue else {
                                return
                            }
                            strongSelf.candidateIncomingVideoNodeValue = nil
                            
                            strongSelf.incomingVideoNodeValue = incomingVideoNode
                            if let expandedVideoNode = strongSelf.expandedVideoNode {
                                strongSelf.minimizedVideoNode = expandedVideoNode
                                strongSelf.videoContainerNode.contentNode.insertSubnode(incomingVideoNode, belowSubnode: expandedVideoNode)
                            } else {
                                strongSelf.videoContainerNode.contentNode.addSubnode(incomingVideoNode)
                            }
                            strongSelf.expandedVideoNode = incomingVideoNode
                            strongSelf.updateButtonsMode(transition: .animated(duration: 0.4, curve: .spring))
                            
                            strongSelf.updateDimVisibility()
                            strongSelf.maybeScheduleUIHidingForActiveVideoCall()
                            strongSelf.dismissKeyPreviewNode()
                        }
                        
                        let incomingVideoNode = CallVideoNode(videoView: incomingVideoView, disabledText: strongSelf.presentationData.strings.Call_RemoteVideoPaused(strongSelf.peer.flatMap(EnginePeer.init)?.compactDisplayTitle ?? "").string, assumeReadyAfterTimeout: false, isReadyUpdated: {
                            if delayUntilInitialized {
                                Queue.mainQueue().after(0.1, {
                                    applyNode()
                                })
                            }
                        }, orientationUpdated: {
                            guard let strongSelf = self else {
                                return
                            }
                            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                            }
                        }, isFlippedUpdated: { _ in
                        })
                        strongSelf.candidateIncomingVideoNodeValue = incomingVideoNode
                        strongSelf.setupAudioOutputs()
                        
                        if !delayUntilInitialized {
                            applyNode()
                        }
                    }
                })
            }
        case .inactive:
            self.candidateIncomingVideoNodeValue = nil
            if let incomingVideoNodeValue = self.incomingVideoNodeValue {
                if self.minimizedVideoNode == incomingVideoNodeValue {
                    self.minimizedVideoNode = nil
                    self.removedMinimizedVideoNodeValue = incomingVideoNodeValue
                }
                if self.expandedVideoNode == incomingVideoNodeValue {
                    self.expandedVideoNode = nil
                    self.removedExpandedVideoNodeValue = incomingVideoNodeValue
                    
                    if let minimizedVideoNode = self.minimizedVideoNode {
                        self.expandedVideoNode = minimizedVideoNode
                        self.minimizedVideoNode = nil
                    }
                }
                self.incomingVideoNodeValue = nil
                self.incomingVideoViewRequested = false
                
                self.dismissKeyPreviewNode()
            }
        }
        
        switch callState.videoState {
        case .active(false), .paused(false):
            if !self.outgoingVideoViewRequested {
                self.outgoingVideoViewRequested = true
                let delayUntilInitialized = self.isRequestingVideo
                self.call.makeOutgoingVideoView(completion: { [weak self] outgoingVideoView in
                    guard let strongSelf = self else {
                        return
                    }
                    
                    if let outgoingVideoView = outgoingVideoView {
                        outgoingVideoView.view.backgroundColor = .black
                        outgoingVideoView.view.clipsToBounds = true
                        
                        let applyNode: () -> Void = {
                            guard let strongSelf = self, let outgoingVideoNode = strongSelf.candidateOutgoingVideoNodeValue else {
                                return
                            }
                            strongSelf.candidateOutgoingVideoNodeValue = nil
                            
                            if strongSelf.isRequestingVideo {
                                strongSelf.isRequestingVideo = false
                                strongSelf.animateRequestedVideoOnce = true
                            }
                            
                            strongSelf.outgoingVideoNodeValue = outgoingVideoNode
                            if let expandedVideoNode = strongSelf.expandedVideoNode {
                                strongSelf.minimizedVideoNode = outgoingVideoNode
                                strongSelf.videoContainerNode.contentNode.insertSubnode(outgoingVideoNode, aboveSubnode: expandedVideoNode)
                            } else {
                                strongSelf.expandedVideoNode = outgoingVideoNode
                                strongSelf.videoContainerNode.contentNode.addSubnode(outgoingVideoNode)
                            }
                            strongSelf.updateButtonsMode(transition: .animated(duration: 0.4, curve: .spring))
                            
                            strongSelf.updateDimVisibility()
                            strongSelf.maybeScheduleUIHidingForActiveVideoCall()
                            strongSelf.dismissKeyPreviewNode()
                        }
                        
                        let outgoingVideoNode = CallVideoNode(videoView: outgoingVideoView, disabledText: nil, assumeReadyAfterTimeout: true, isReadyUpdated: {
                            if delayUntilInitialized {
                                Queue.mainQueue().after(0.4, {
                                    applyNode()
                                })
                            }
                        }, orientationUpdated: {
                            guard let strongSelf = self else {
                                return
                            }
                            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                            }
                        }, isFlippedUpdated: { videoNode in
                            guard let _ = self else {
                                return
                            }
                            /*if videoNode === strongSelf.minimizedVideoNode, let tempView = videoNode.view.snapshotView(afterScreenUpdates: true) {
                                videoNode.view.superview?.insertSubview(tempView, aboveSubview: videoNode.view)
                                videoNode.view.frame = videoNode.frame
                                let transitionOptions: UIView.AnimationOptions = [.transitionFlipFromRight, .showHideTransitionViews]

                                UIView.transition(with: tempView, duration: 1.0, options: transitionOptions, animations: {
                                    tempView.isHidden = true
                                }, completion: { [weak tempView] _ in
                                    tempView?.removeFromSuperview()
                                })

                                videoNode.view.isHidden = true
                                UIView.transition(with: videoNode.view, duration: 1.0, options: transitionOptions, animations: {
                                    videoNode.view.isHidden = false
                                })
                            }*/
                        })
                        
                        strongSelf.candidateOutgoingVideoNodeValue = outgoingVideoNode
                        strongSelf.setupAudioOutputs()
                        
                        if !delayUntilInitialized {
                            applyNode()
                        }
                    }
                })
            }
        default:
            self.candidateOutgoingVideoNodeValue = nil
            if let outgoingVideoNodeValue = self.outgoingVideoNodeValue {
                if self.minimizedVideoNode == outgoingVideoNodeValue {
                    self.minimizedVideoNode = nil
                    self.removedMinimizedVideoNodeValue = outgoingVideoNodeValue
                }
                if self.expandedVideoNode == self.outgoingVideoNodeValue {
                    self.expandedVideoNode = nil
                    self.removedExpandedVideoNodeValue = outgoingVideoNodeValue
                    
                    if let minimizedVideoNode = self.minimizedVideoNode {
                        self.expandedVideoNode = minimizedVideoNode
                        self.minimizedVideoNode = nil
                    }
                }
                self.outgoingVideoNodeValue = nil
                self.outgoingVideoViewRequested = false
                
                self.dismissKeyPreviewNode()
            }
        }
        
        if let incomingVideoNode = self.incomingVideoNodeValue {
            switch callState.state {
            case .terminating, .terminated:
                break
            default:
                let isActive: Bool
                switch callState.remoteVideoState {
                case .inactive, .paused:
                    isActive = false
                case .active:
                    isActive = true
                }
                incomingVideoNode.updateIsBlurred(isBlurred: !isActive)
            }
        }
                
        switch callState.state {
            case .waiting, .connecting:
                statusValue = .text(string: self.presentationData.strings.Call_StatusConnecting, displayLogo: false)
            case let .requesting(ringing):
                if ringing {
                    statusValue = .text(string: self.presentationData.strings.Call_StatusRinging, displayLogo: false)
                } else {
                    statusValue = .text(string: self.presentationData.strings.Call_StatusRequesting, displayLogo: false)
                }
            case .terminating:
                self.statusNode.title = self.presentationData.strings.Call_StatusEnded
                statusReception = .min
                statusValue = .timer({ value, _ in
                    self.currentCallTimestamp == nil ? "00:00" : value
                }, self.currentCallTimestamp ?? 0.0)
            case let .terminated(_, reason, _):
                if let reason = reason {
                    switch reason {
                        case let .ended(type):
                            switch type {
                                case .busy:
                                    statusValue = .text(string: self.presentationData.strings.Call_StatusBusy, displayLogo: false)
                                case .hungUp, .missed:
                                    self.statusNode.title = self.presentationData.strings.Call_StatusEnded
                                    statusReception = .min
                                    statusValue = .timer({ value, _ in
                                        self.currentCallTimestamp == nil ? "00:00" : value
                                    }, self.currentCallTimestamp ?? 0.0)
                            }
                        case let .error(error):
                            let text = self.presentationData.strings.Call_StatusFailed
                            switch error {
                            case let .notSupportedByPeer(isVideo):
                                if !self.displayedVersionOutdatedAlert, let peer = self.peer {
                                    self.displayedVersionOutdatedAlert = true
                                    
                                    let text: String
                                    if isVideo {
                                        text = self.presentationData.strings.Call_ParticipantVideoVersionOutdatedError(EnginePeer(peer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)).string
                                    } else {
                                        text = self.presentationData.strings.Call_ParticipantVersionOutdatedError(EnginePeer(peer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)).string
                                    }
                                    
                                    self.present?(textAlertController(sharedContext: self.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {
                                    })]))
                                }
                            default:
                                break
                            }
                            statusValue = .text(string: text, displayLogo: false)
                    }
                } else {
                    self.statusNode.title = self.presentationData.strings.Call_StatusEnded
                    statusReception = .min
                    statusValue = .timer({ value, _ in
                        self.currentCallTimestamp == nil ? "00:00" : value
                    }, self.currentCallTimestamp ?? 0.0)
                }
                Queue.mainQueue().async { [weak self] in
                    self?.playCallEndedAnimation()
                }
            case .ringing:
                var text: String
                if self.call.isVideo {
                    text = self.presentationData.strings.Call_IncomingVideoCall
                } else {
                    text = self.presentationData.strings.Call_IncomingVoiceCall
                }
                if !self.statusNode.subtitle.isEmpty {
                    text += "\n\(self.statusNode.subtitle)"
                }
                statusValue = .text(string: text, displayLogo: false)
            case .active(let timestamp, let reception, let keyVisualHash), .reconnecting(let timestamp, let reception, let keyVisualHash):
                let strings = self.presentationData.strings
                var isReconnecting = false
                if case .reconnecting = callState.state {
                    isReconnecting = true
                }
                if self.keyTextData?.0 != keyVisualHash {
                    let text = stringForEmojiHashOfData(keyVisualHash, 4)!
                    self.keyTextData = (keyVisualHash, text)

                    self.keyButtonNode.key = text
                    self.keyPreviewNode.keyText = text
                    
                    let keyTextSize = self.keyButtonNode.measure(CGSize(width: 200.0, height: 200.0))
                    self.keyButtonNode.frame = CGRect(origin: self.keyButtonNode.frame.origin, size: keyTextSize)
                    
                    if let (layout, navigationBarHeight) = self.validLayout {
                        self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
                    }
                    
                    self.playCallStartedAnimation()
                    self.displayEncryptionKeyTooltip()
                    self.avatarNode.playConnectedAnimation()
                }
                
                Queue.mainQueue().async { [weak self] in
                    self?.playReceptionChangedAnimation(reception: reception ?? 0)
                }
                self.currentCallTimestamp = timestamp
                
                statusValue = .timer({ value, measure in
                    if isReconnecting || (self.outgoingVideoViewRequested && value == "00:00" && !measure) {
                        return strings.Call_StatusConnecting
                    } else {
                        return value
                    }
                }, timestamp)
                if case .active = callState.state {
                    statusReception = reception
                }
        }
        if self.shouldStayHiddenUntilConnection {
            switch callState.state {
                case .connecting, .active:
                    self.containerNode.alpha = 1.0
                default:
                    break
            }
        }
        self.statusNode.status = statusValue
        self.statusNode.reception = statusReception
        
        if let callState = self.callState {
            switch callState.state {
            case .active, .connecting, .reconnecting:
                break
            case .terminating, .terminated:
                if self.outgoingVideoNodeValue != nil {
                    self.call.disableVideo()
                    self.cancelScheduledUIHiding()
                }
                fallthrough
            default:
                self.isUIHidden = false
            }
        }
        
        if case .muted = callState.remoteAudioState {
            self.avatarNode.playMuteAnimation()
        } else {
            self.avatarNode.playUnmuteAnimation()
        }
        
        self.updateToastContent()
        self.updateButtonsMode()
        self.updateDimVisibility()
        
        if case let .terminated(id, _, reportRating) = callState.state, let callId = id {
            let presentRating = reportRating || self.forceReportRating
            if presentRating {
                let isVideo = self.call.isVideo
                self.ratingNode.apply = { [weak self] rating in
                    self?.sendCallRating?(callId, isVideo, rating)
                }
                self.ratingNode.isHidden = false
                self.ratingNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                self.ratingNode.layer.animateSpring(from: 0.75 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.25)
            }
            self.callEnded?(presentRating)
        }
        
        let hasIncomingVideoNode = self.incomingVideoNodeValue != nil && self.expandedVideoNode === self.incomingVideoNodeValue
        self.videoContainerNode.isPinchGestureEnabled = hasIncomingVideoNode
    }
    
    private func updateToastContent() {
        guard let callState = self.callState else {
            return
        }
        if case .terminating = callState.state {
        } else if case .terminated = callState.state {
        } else {
            var toastContent: CallControllerToastContent = []
            if case .active = callState.state {
                if let displayToastsAfterTimestamp = self.displayToastsAfterTimestamp {
                    if CACurrentMediaTime() > displayToastsAfterTimestamp {
                        if case .inactive = callState.remoteVideoState, self.hasVideoNodes {
                            toastContent.insert(.camera)
                        }
                        if case .muted = callState.remoteAudioState {
                            toastContent.insert(.microphone)
                        }
                        if case .low = callState.remoteBatteryLevel {
                            toastContent.insert(.battery)
                        }
                    }
                } else {
                    self.displayToastsAfterTimestamp = CACurrentMediaTime() + 1.5
                }
            }
            if self.isMuted {
                toastContent.insert(.mute)
            }
            self.toastContent = toastContent
        }
    }
    
    private func updateDimVisibility(transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)) {
        guard let callState = self.callState else {
            return
        }
        
        var visible = true
        if case .active = callState.state, self.hasVideo {
            visible = false
        }
        
        let currentVisible = self.dimNode.image == nil
        if visible != currentVisible {
            let color = visible ? UIColor(rgb: 0x000000, alpha: 0.3) : UIColor.clear
            let image: UIImage? = visible ? nil : generateGradientImage(size: CGSize(width: 1.0, height: 640.0), colors: [UIColor.black.withAlphaComponent(0.3), UIColor.clear, UIColor.clear, UIColor.black.withAlphaComponent(0.3)], locations: [0.0, 0.22, 0.7, 1.0])
            if case let .animated(duration, _) = transition {
                UIView.transition(with: self.dimNode.view, duration: duration, options: .transitionCrossDissolve, animations: {
                    self.dimNode.backgroundColor = color
                    self.dimNode.image = image
                }, completion: nil)
            } else {
                self.dimNode.backgroundColor = color
                self.dimNode.image = image
            }
        }
    }
    
    private func maybeScheduleUIHidingForActiveVideoCall() {
        guard let callState = self.callState, case .active = callState.state, self.incomingVideoNodeValue != nil && self.outgoingVideoNodeValue != nil, !self.hiddenUIForActiveVideoCallOnce && self.keyPreviewNode.isHidden else {
            return
        }
        
        let timer = SwiftSignalKit.Timer(timeout: 3.0, repeat: false, completion: { [weak self] in
            if let strongSelf = self {
                var updated = false
                if let callState = strongSelf.callState, !strongSelf.isUIHidden {
                    switch callState.state {
                        case .active, .connecting, .reconnecting:
                            strongSelf.isUIHidden = true
                            updated = true
                        default:
                            break
                    }
                }
                if updated, let (layout, navigationBarHeight) = strongSelf.validLayout {
                    strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                }
                strongSelf.hideUIForActiveVideoCallTimer = nil
            }
        }, queue: Queue.mainQueue())
        timer.start()
        self.hideUIForActiveVideoCallTimer = timer
        self.hiddenUIForActiveVideoCallOnce = true
    }
    
    private func cancelScheduledUIHiding() {
        self.hideUIForActiveVideoCallTimer?.invalidate()
        self.hideUIForActiveVideoCallTimer = nil
    }
    
    private var buttonsTerminationMode: CallControllerButtonsMode?
    
    private func updateButtonsMode(transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .spring)) {
        guard let callState = self.callState else {
            return
        }
        
        var mode: CallControllerButtonsSpeakerMode = .none
        var hasAudioRouteMenu: Bool = false
        if let (availableOutputs, maybeCurrentOutput) = self.audioOutputState, let currentOutput = maybeCurrentOutput {
            hasAudioRouteMenu = availableOutputs.count > 2
            switch currentOutput {
                case .builtin:
                    mode = .builtin
                case .speaker:
                    mode = .speaker
                case .headphones:
                    mode = .headphones
                case let .port(port):
                    var type: CallControllerButtonsSpeakerMode.BluetoothType = .generic
                    let portName = port.name.lowercased()
                    if portName.contains("airpods pro") {
                        type = .airpodsPro
                    } else if portName.contains("airpods") {
                        type = .airpods
                    }
                    mode = .bluetooth(type)
            }
            if availableOutputs.count <= 1 {
                mode = .none
            }
        }
        var mappedVideoState = CallControllerButtonsMode.VideoState(isAvailable: false, isCameraActive: self.outgoingVideoNodeValue != nil, isScreencastActive: false, canChangeStatus: false, hasVideo: self.hasVideo, isInitializingCamera: self.isRequestingVideo)
        switch callState.videoState {
        case .notAvailable:
            break
        case .inactive:
            mappedVideoState.isAvailable = true
            mappedVideoState.canChangeStatus = true
        case .active(let isScreencast), .paused(let isScreencast):
            mappedVideoState.isAvailable = true
            mappedVideoState.canChangeStatus = true
            if isScreencast {
                mappedVideoState.isScreencastActive = true
                mappedVideoState.hasVideo = true
            }
        }
        
        switch callState.state {
        case .ringing:
            self.buttonsMode = .incoming(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            self.buttonsTerminationMode = buttonsMode
        case .waiting, .requesting:
            self.buttonsMode = .outgoingRinging(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            self.buttonsTerminationMode = buttonsMode
        case .active, .connecting, .reconnecting:
            self.buttonsMode = .active(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            self.buttonsTerminationMode = buttonsMode
        case .terminating, .terminated:
            if let buttonsTerminationMode = self.buttonsTerminationMode {
                self.buttonsMode = buttonsTerminationMode
            } else {
                self.buttonsMode = .active(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            }
        }
                
        if let (layout, navigationHeight) = self.validLayout {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: transition)
        }
    }
    
    func animateIn() {
        if !self.containerNode.alpha.isZero {
            var bounds = self.bounds
            bounds.origin = CGPoint()
            self.bounds = bounds
            self.layer.removeAnimation(forKey: "bounds")
            self.statusBar.layer.removeAnimation(forKey: "opacity")
            self.containerNode.layer.removeAnimation(forKey: "opacity")
            self.containerNode.layer.removeAnimation(forKey: "scale")
            self.statusBar.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
            if !self.shouldStayHiddenUntilConnection {
                self.containerNode.layer.animateScale(from: 1.04, to: 1.0, duration: 0.3)
                self.containerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
            }
        }
    }
    
    func animateOut(completion: @escaping () -> Void) {
        self.statusBar.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false)
        if !self.shouldStayHiddenUntilConnection || self.containerNode.alpha > 0.0 {
            self.containerNode.layer.allowsGroupOpacity = true
            self.containerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak self] _ in
                self?.containerNode.layer.allowsGroupOpacity = false
            })
            self.containerNode.layer.animateScale(from: 1.0, to: 1.04, duration: 0.3, removeOnCompletion: false, completion: { _ in
                completion()
            })
        } else {
            completion()
        }
    }
    
    private func startBackgroundAnimation() {
        guard self.backgroundAnimationTimer == nil else { return }
        self.backgroundAnimationTimer = SwiftSignalKit.Timer(timeout: 0.5, repeat: true, completion: { [weak self] in
            let transition = ContainedViewLayoutTransition.animated(duration: 0.5, curve: .linear)
            self?.backgroundNode.animateEvent(transition: transition, extendAnimation: false, backwards: false, completion: {})
        }, queue: .mainQueue())
        self.backgroundAnimationTimer?.start()
    }
    
    private func stopBackgroundAnimation() {
        self.backgroundAnimationTimer?.invalidate()
        self.backgroundAnimationTimer = nil
    }
    
    private func updateBackground(to gradient: BackgroundGradient) {
        guard self.currentBackground != gradient else { return }
        self.currentBackground = gradient
        
        UIView.transition(with: self.backgroundNode.view, duration: 1.0 / 3.0, options: [.curveEaseInOut, .transitionCrossDissolve]) { [weak self] in
            self?.backgroundNode.updateColors(colors: gradient.colors)
        }
    }
    
    private var animatingCallStarted = false
    private func playCallStartedAnimation() {
        guard !self.animatingCallStarted else { return }
        self.animatingCallStarted = true
        
        if self.keyButtonNode.isHidden {
            self.keyButtonNode.isHidden = false
            self.keyButtonNode.animateIn()
        }
        
        if self.backButtonNode.isHidden {
            self.backButtonNode.isHidden = false
            let position = self.backButtonNode.layer.position
            self.backButtonNode.layer.animatePosition(from: position.offsetBy(dx: 15.0, dy: 0.0), to: position, duration: 0.3)
            self.backButtonNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
        }
        
        if self.backButtonArrowNode.isHidden {
            self.backButtonArrowNode.isHidden = false
            let position = self.backButtonArrowNode.layer.position
            self.backButtonArrowNode.layer.animatePosition(from: position.offsetBy(dx: 10.0, dy: 0.0), to: position, duration: 0.3)
            self.backButtonArrowNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
        }
    }
    
    private var animatingCallEnded = false
    private func playCallEndedAnimation() {
        guard !self.animatingCallEnded else { return }
        self.animatingCallEnded = true
        
        self.dismissKeyPreviewNode()
        self.avatarNode.playMuteAnimation()
        self.updateBackground(to: .blueViolet)
        
        self.closeButtonNode.isHidden = false
        self.closeButtonNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 1.0 / 3.0, removeOnCompletion: false, completion: { [weak self] _ in
            self?.closeButtonNode.animateProgress(duration: 5.0)
            Queue.mainQueue().after(5.0) { [weak self] in
                self?.animatingCallEnded = false
                self?.closePressed()
            }
        })
        
        if let endButtonFrame = self.buttonsNode.endButtonFrame().flatMap({
            self.buttonsNode.view.convert($0, to: self.view)
        }) {
            self.closeButtonNode.layer.animateFrame(from: endButtonFrame, to: self.closeButtonNode.frame, duration: 0.25)
        }
        
        for node in [self.buttonsNode, self.backButtonNode, self.backButtonArrowNode, self.keyButtonNode, self.toastNode, self.weakNetworkToastNode] {
            node.layer.animateAlpha(from: 1.0, to: 0.0, duration: 1.0 / 3.0, removeOnCompletion: false, completion: { [weak node] _ in
                node?.removeFromSupernode()
            })
        }
    }
    
    private func playReceptionChangedAnimation(reception: Int32) {
        let weakNetwork = reception <= 1
        if weakNetwork {
            self.updateBackground(to: .orangeRed)
            if self.weakNetworkToastNode.isHidden {
                self.weakNetworkToastNode.isHidden = false
                self.weakNetworkToastNode.animateIn()
            }
        } else {
            self.updateBackground(to: .blueGreen)
            if !self.weakNetworkToastNode.isHidden {
                self.weakNetworkToastNode.animateOut(transition: .animated(duration: 0.3, curve: .spring)) { [weak self] in
                    self?.weakNetworkToastNode.isHidden = true
                }
            }
        }
    }
    
    func expandFromPipIfPossible() {
        if self.pictureInPictureTransitionFraction.isEqual(to: 1.0), let (layout, navigationHeight) = self.validLayout {
            self.pictureInPictureTransitionFraction = 0.0
            
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
        }
    }
    
    private func calculatePreviewVideoRect(layout: ContainerViewLayout, navigationHeight: CGFloat) -> CGRect {
        let buttonsHeight: CGFloat = self.buttonsNode.bounds.height
        let toastHeight: CGFloat = self.toastNode.bounds.height
        let toastInset = (toastHeight > 0.0 ? toastHeight + 16.0 : 0.0)
        
        var fullInsets = layout.insets(options: .statusBar)
    
        var cleanInsets = fullInsets
        cleanInsets.bottom = max(layout.intrinsicInsets.bottom, 20.0) + max(toastInset, 16.0)
        cleanInsets.left = 10.0
        cleanInsets.right = 10.0
        
        fullInsets.top += 44.0 + 8.0
        fullInsets.bottom = buttonsHeight + 16.0 + toastInset
        fullInsets.left = 10.0
        fullInsets.right = 10.0
        
        var insets: UIEdgeInsets = self.isUIHidden ? cleanInsets : fullInsets
        let maxPreviewVideoSide: CGFloat = self.isUIHidden ? 140.0 : 240.0
        
        let expandedInset: CGFloat = 16.0
        
        insets.top = interpolate(from: expandedInset, to: insets.top, value: 1.0 - self.pictureInPictureTransitionFraction)
        insets.bottom = interpolate(from: expandedInset, to: insets.bottom, value: 1.0 - self.pictureInPictureTransitionFraction)
        insets.left = interpolate(from: expandedInset, to: insets.left, value: 1.0 - self.pictureInPictureTransitionFraction)
        insets.right = interpolate(from: expandedInset, to: insets.right, value: 1.0 - self.pictureInPictureTransitionFraction)
        
        let previewVideoSide = interpolate(from: 300.0, to: maxPreviewVideoSide, value: 1.0 - self.pictureInPictureTransitionFraction)
        var previewVideoSize = layout.size.aspectFitted(CGSize(width: previewVideoSide, height: previewVideoSide))
        previewVideoSize = CGSize(width: 30.0, height: 45.0).aspectFitted(previewVideoSize)
        if let minimizedVideoNode = self.minimizedVideoNode {
            var aspect = minimizedVideoNode.currentAspect
            var rotationCount = 0
            if minimizedVideoNode === self.outgoingVideoNodeValue {
                aspect = 23.0 / 40.0
            } else {
                if aspect < 1.0 {
                    aspect = 23.0 / 40.0
                } else {
                    aspect = 40.0 / 23.0
                }
                
                switch minimizedVideoNode.currentOrientation {
                case .rotation90, .rotation270:
                    rotationCount += 1
                default:
                    break
                }
                
                var mappedDeviceOrientation = self.deviceOrientation
                if case .regular = layout.metrics.widthClass, case .regular = layout.metrics.heightClass {
                    mappedDeviceOrientation = .portrait
                }
                
                switch mappedDeviceOrientation {
                case .landscapeLeft, .landscapeRight:
                    rotationCount += 1
                default:
                    break
                }
                
                if rotationCount % 2 != 0 {
                    aspect = 1.0 / aspect
                }
            }
            
            let unboundVideoSize = CGSize(width: aspect * 10000.0, height: 10000.0)
            
            previewVideoSize = unboundVideoSize.aspectFitted(CGSize(width: previewVideoSide, height: previewVideoSide))
        }
        let previewVideoY: CGFloat
        let previewVideoX: CGFloat
        
        switch self.outgoingVideoNodeCorner {
        case .topLeft:
            previewVideoX = insets.left
            previewVideoY = insets.top
        case .topRight:
            previewVideoX = layout.size.width - previewVideoSize.width - insets.right
            previewVideoY = insets.top
        case .bottomLeft:
            previewVideoX = insets.left
            previewVideoY = layout.size.height - insets.bottom - previewVideoSize.height
        case .bottomRight:
            previewVideoX = layout.size.width - previewVideoSize.width - insets.right
            previewVideoY = layout.size.height - insets.bottom - previewVideoSize.height
        }
        
        return CGRect(origin: CGPoint(x: previewVideoX, y: previewVideoY), size: previewVideoSize)
    }
    
    private func calculatePictureInPictureContainerRect(layout: ContainerViewLayout, navigationHeight: CGFloat) -> CGRect {
        let pictureInPictureTopInset: CGFloat = layout.insets(options: .statusBar).top + 44.0 + 8.0
        let pictureInPictureSideInset: CGFloat = 8.0
        let pictureInPictureSize = layout.size.fitted(CGSize(width: 240.0, height: 240.0))
        let pictureInPictureBottomInset: CGFloat = layout.insets(options: .input).bottom + 44.0 + 8.0
        
        let containerPictureInPictureFrame: CGRect
        switch self.pictureInPictureCorner {
        case .topLeft:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: pictureInPictureSideInset, y: pictureInPictureTopInset), size: pictureInPictureSize)
        case .topRight:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: layout.size.width -  pictureInPictureSideInset - pictureInPictureSize.width, y: pictureInPictureTopInset), size: pictureInPictureSize)
        case .bottomLeft:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: pictureInPictureSideInset, y: layout.size.height - pictureInPictureBottomInset - pictureInPictureSize.height), size: pictureInPictureSize)
        case .bottomRight:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: layout.size.width -  pictureInPictureSideInset - pictureInPictureSize.width, y: layout.size.height - pictureInPictureBottomInset - pictureInPictureSize.height), size: pictureInPictureSize)
        }
        return containerPictureInPictureFrame
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = (layout, navigationBarHeight)
        
        var mappedDeviceOrientation = self.deviceOrientation
        var isCompactLayout = true
        if case .regular = layout.metrics.widthClass, case .regular = layout.metrics.heightClass {
            mappedDeviceOrientation = .portrait
            isCompactLayout = false
        }
        
        if !self.hasVideoNodes {
            self.isUIHidden = false
        }
        
        var isUIHidden = self.isUIHidden
        switch self.callState?.state {
        case .terminated, .terminating:
            isUIHidden = false
        default:
            break
        }
        
        var uiDisplayTransition: CGFloat = isUIHidden ? 0.0 : 1.0
        let pipTransitionAlpha: CGFloat = 1.0 - self.pictureInPictureTransitionFraction
        uiDisplayTransition *= pipTransitionAlpha
        
        let pinchTransitionAlpha: CGFloat = self.isVideoPinched ? 0.0 : 1.0
        
        let previousVideoButtonFrame = self.buttonsNode.videoButtonFrame().flatMap { frame -> CGRect in
            return self.buttonsNode.view.convert(frame, to: self.view)
        }
        
        let buttonsHeight: CGFloat
        if let buttonsMode = self.buttonsMode {
            buttonsHeight = self.buttonsNode.updateLayout(strings: self.presentationData.strings, mode: buttonsMode, constrainedWidth: layout.size.width, bottomInset: layout.intrinsicInsets.bottom, transition: transition)
        } else {
            buttonsHeight = 0.0
        }
        let defaultButtonsOriginY = layout.size.height - buttonsHeight
        let buttonsCollapsedOriginY = self.pictureInPictureTransitionFraction > 0.0 ? layout.size.height + 30.0 : layout.size.height + 10.0
        let buttonsOriginY = interpolate(from: buttonsCollapsedOriginY, to: defaultButtonsOriginY, value: uiDisplayTransition)
        
        let toastHeight = self.toastNode.updateLayout(strings: self.presentationData.strings, content: self.toastContent, lightStyle: !self.hasVideo, constrainedWidth: layout.size.width, bottomInset: layout.intrinsicInsets.bottom + buttonsHeight, transition: transition)
        let toastSpacing: CGFloat = 16.0
        let toastCollapsedOriginY = self.pictureInPictureTransitionFraction > 0.0 ? layout.size.height : layout.size.height - max(layout.intrinsicInsets.bottom, 20.0) - toastHeight
        let toastOriginY = interpolate(from: toastCollapsedOriginY, to: defaultButtonsOriginY - toastSpacing - toastHeight, value: uiDisplayTransition)
        
        let overlayAlpha: CGFloat = min(pinchTransitionAlpha, uiDisplayTransition)
        let toastAlpha: CGFloat = min(pinchTransitionAlpha, pipTransitionAlpha)
        
        let containerFullScreenFrame = CGRect(origin: CGPoint(), size: layout.size)
        let containerPictureInPictureFrame = self.calculatePictureInPictureContainerRect(layout: layout, navigationHeight: navigationBarHeight)
        
        let containerFrame = interpolateFrame(from: containerFullScreenFrame, to: containerPictureInPictureFrame, t: self.pictureInPictureTransitionFraction)
        
        transition.updateFrame(node: self.containerTransformationNode, frame: containerFrame)
        transition.updateSublayerTransformScale(node: self.containerTransformationNode, scale: min(1.0, containerFrame.width / layout.size.width * 1.01))
        transition.updateCornerRadius(layer: self.containerTransformationNode.layer, cornerRadius: self.pictureInPictureTransitionFraction * 10.0)
        
        transition.updateFrame(node: self.containerNode, frame: CGRect(origin: CGPoint(x: (containerFrame.width - layout.size.width) / 2.0, y: floor(containerFrame.height - layout.size.height) / 2.0), size: layout.size))
        transition.updateFrame(node: self.videoContainerNode, frame: containerFullScreenFrame)
        self.videoContainerNode.update(size: containerFullScreenFrame.size, transition: transition)
        
        transition.updateAlpha(node: self.dimNode, alpha: pinchTransitionAlpha)
        transition.updateFrame(node: self.dimNode, frame: containerFullScreenFrame)
        
        self.backgroundNode.updateLayout(size: layout.size, transition: transition, extendAnimation: false, backwards: false, completion: {})
        transition.updateFrame(node: self.backgroundNode, frame: containerFullScreenFrame)
        
        let maybeTopSafeArea: CGFloat
        if layout.statusBarHeight == 54.0 {
            // Workaround for iPhone 14 Pro / Pro Max
            maybeTopSafeArea = 59.0
        } else {
            maybeTopSafeArea = 0.0
        }
        
        let navigationOffset: CGFloat = max(20.0, layout.safeInsets.top, maybeTopSafeArea)
        let topOriginY = interpolate(from: -20.0, to: navigationOffset, value: uiDisplayTransition)
        
        let backSize = self.backButtonNode.measure(CGSize(width: 320.0, height: 100.0))
        if let image = self.backButtonArrowNode.image {
            transition.updateFrame(node: self.backButtonArrowNode, frame: CGRect(origin: CGPoint(x: 10.0, y: topOriginY + 11.0), size: image.size))
        }
        transition.updateFrame(node: self.backButtonNode, frame: CGRect(origin: CGPoint(x: 29.0, y: topOriginY + 11.0), size: backSize))
        
        transition.updateAlpha(node: self.backButtonArrowNode, alpha: overlayAlpha)
        transition.updateAlpha(node: self.backButtonNode, alpha: overlayAlpha)
        transition.updateAlpha(node: self.toastNode, alpha: toastAlpha)
        transition.updateAlpha(node: self.weakNetworkToastNode, alpha: overlayAlpha)
        
        let keyPreviewOrigin = CGPoint(x: (layout.size.width - self.keyPreviewNodeSize.width) / 2.0, y: topOriginY + 73.0)
        transition.updateFrame(node: keyPreviewNode, frame: CGRect(origin: keyPreviewOrigin, size: self.keyPreviewNodeSize))
        transition.updateAlpha(node: keyPreviewNode, alpha: overlayAlpha)
        keyPreviewNode.updateLayout(size: self.keyPreviewNodeSize, transition: .immediate)
        
        let avatarSize = CGSize(width: 136.0, height: 136.0)
        let avatarOrigin = CGPoint(x: (containerFullScreenFrame.width - avatarSize.width) / 2, y: topOriginY + 163.0)
        transition.updateFrame(node: self.avatarNode, frame: CGRect(origin: avatarOrigin, size: avatarSize))
        
        // TODO: Maybe truncate status node
        let statusHeight = self.statusNode.updateLayout(constrainedWidth: layout.size.width, reducedSize: self.hasVideo, transition: transition)
        transition.updateFrame(node: self.statusNode, frame: CGRect(origin: CGPoint(x: 0.0, y: self.hasVideo ? topOriginY : avatarOrigin.y + avatarSize.height + 40.0), size: CGSize(width: layout.size.width, height: statusHeight)))
        transition.updateAlpha(node: self.statusNode, alpha: overlayAlpha)
        
        transition.updateFrame(node: self.toastNode, frame: CGRect(origin: CGPoint(x: 0.0, y: toastOriginY), size: CGSize(width: layout.size.width, height: toastHeight)))
        transition.updateFrame(node: self.buttonsNode, frame: CGRect(origin: CGPoint(x: 0.0, y: buttonsOriginY), size: CGSize(width: layout.size.width, height: buttonsHeight)))
        transition.updateAlpha(node: self.buttonsNode, alpha: overlayAlpha)
        
        let weakNetworkToastHeight = self.weakNetworkToastNode.update(width: layout.size.width, content: .weakNetwork, lightStyle: !self.hasVideo, transition: transition)
        transition.updateFrame(node: self.weakNetworkToastNode, frame: CGRect(origin: CGPoint(x: 0.0, y: self.statusNode.frame.maxY + 12.0), size: CGSize(width: layout.size.width, height: weakNetworkToastHeight)))
        
        let ratingNodeWidth = min(layout.size.width - 89.0, 304.0)
        let ratingNodeHeight = self.ratingNode.updateLayout(constrainedWidth: ratingNodeWidth, transition: transition)
        self.ratingNode.frame = CGRect(x: (layout.size.width - ratingNodeWidth) / 2.0, y: self.statusNode.frame.maxY + 50.0, width: ratingNodeWidth, height: ratingNodeHeight)
        
        let closeButtonSize = CGSize(width: ratingNodeWidth, height: 50.0)
        self.closeButtonNode.updateLayout(size: closeButtonSize, transition: transition)
        transition.updateFrame(node: self.closeButtonNode, frame: CGRect(origin: CGPoint(x: (layout.size.width - closeButtonSize.width) / 2.0, y: buttonsOriginY + 3.0), size: closeButtonSize))
        
        let fullscreenVideoFrame = containerFullScreenFrame
        let previewVideoFrame = self.calculatePreviewVideoRect(layout: layout, navigationHeight: navigationBarHeight)
        
        if let removedMinimizedVideoNodeValue = self.removedMinimizedVideoNodeValue {
            self.removedMinimizedVideoNodeValue = nil
            
            if transition.isAnimated {
                removedMinimizedVideoNodeValue.layer.animateScale(from: 1.0, to: 0.1, duration: 0.3, removeOnCompletion: false)
                removedMinimizedVideoNodeValue.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak removedMinimizedVideoNodeValue] _ in
                    removedMinimizedVideoNodeValue?.removeFromSupernode()
                })
            } else {
                removedMinimizedVideoNodeValue.removeFromSupernode()
            }
        }
        
        // FIXME: Using private API to match the transition from the mock-up
        let displayCornerRadius = UIScreen.main.value(forKey: "_displayCornerRadius") as? CGFloat
        
        if let expandedVideoNode = self.expandedVideoNode {
            transition.updateAlpha(node: expandedVideoNode, alpha: 1.0)
            var expandedVideoTransition = transition
            if expandedVideoNode.frame.isEmpty || self.disableAnimationForExpandedVideoOnce {
                expandedVideoTransition = .immediate
                self.disableAnimationForExpandedVideoOnce = false
            }
            
            if let removedExpandedVideoNodeValue = self.removedExpandedVideoNodeValue {
                self.removedExpandedVideoNodeValue = nil
                
                expandedVideoTransition.updateFrame(node: expandedVideoNode, frame: fullscreenVideoFrame, completion: { [weak removedExpandedVideoNodeValue] _ in
                    removedExpandedVideoNodeValue?.removeFromSupernode()
                })
            } else {
                expandedVideoTransition.updateFrame(node: expandedVideoNode, frame: fullscreenVideoFrame)
            }
            
            expandedVideoNode.updateLayout(size: expandedVideoNode.frame.size, cornerRadius: 0.0, isOutgoing: expandedVideoNode === self.outgoingVideoNodeValue, deviceOrientation: mappedDeviceOrientation, isCompactLayout: isCompactLayout, transition: expandedVideoTransition)
            
            if self.animateRequestedVideoOnce {
                self.animateRequestedVideoOnce = false
                if expandedVideoNode === self.outgoingVideoNodeValue {
                    let videoButtonFrame = self.buttonsNode.videoButtonFrame().flatMap { frame -> CGRect in
                        return self.buttonsNode.view.convert(frame, to: self.view)
                    }
                    
                    if let previousVideoButtonFrame = previousVideoButtonFrame, let videoButtonFrame = videoButtonFrame {
                        expandedVideoNode.animateRadialMask(from: previousVideoButtonFrame, to: videoButtonFrame)
                    }
                }
            }
            
            if expandedVideoNode === self.incomingVideoNodeValue && !expandedVideoTransition.isAnimated {
                expandedVideoNode.layer.animate(from: (avatarSize.width / 2.0) as NSNumber, to: (displayCornerRadius ?? 0.0) as NSNumber, keyPath: "cornerRadius", timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, duration: 0.3)
                expandedVideoNode.layer.animateFrame(from: self.avatarNode.frame, to: fullscreenVideoFrame, duration: 0.3)
                expandedVideoNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
            }
        } else {
            if let removedExpandedVideoNodeValue = self.removedExpandedVideoNodeValue {
                self.removedExpandedVideoNodeValue = nil
                
                if transition.isAnimated {
                    removedExpandedVideoNodeValue.layer.animate(from: (displayCornerRadius ?? 0.0) as NSNumber, to: (avatarSize.width / 2.0) as NSNumber, keyPath: "cornerRadius", timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, duration: 0.3, removeOnCompletion: false)
                    removedExpandedVideoNodeValue.layer.animateFrame(from: removedExpandedVideoNodeValue.frame, to: self.avatarNode.frame, duration: 0.3, removeOnCompletion: false)
                    removedExpandedVideoNodeValue.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak removedExpandedVideoNodeValue] _ in
                        removedExpandedVideoNodeValue?.removeFromSupernode()
                    })
                } else {
                    removedExpandedVideoNodeValue.removeFromSupernode()
                }
            }
        }
        
        
        if let minimizedVideoNode = self.minimizedVideoNode {
            transition.updateAlpha(node: minimizedVideoNode, alpha: min(pipTransitionAlpha, pinchTransitionAlpha))
            var minimizedVideoTransition = transition
            var didAppear = false
            if minimizedVideoNode.frame.isEmpty {
                minimizedVideoTransition = .immediate
                didAppear = true
            }
            if self.minimizedVideoDraggingPosition == nil {
                if let animationForExpandedVideoSnapshotView = self.animationForExpandedVideoSnapshotView {
                    self.containerNode.view.addSubview(animationForExpandedVideoSnapshotView)
                    transition.updateAlpha(layer: animationForExpandedVideoSnapshotView.layer, alpha: 0.0, completion: { [weak animationForExpandedVideoSnapshotView] _ in
                        animationForExpandedVideoSnapshotView?.removeFromSuperview()
                    })
                    transition.updateTransformScale(layer: animationForExpandedVideoSnapshotView.layer, scale: previewVideoFrame.width / fullscreenVideoFrame.width)
                    
                    transition.updatePosition(layer: animationForExpandedVideoSnapshotView.layer, position: CGPoint(x: previewVideoFrame.minX + previewVideoFrame.center.x /  fullscreenVideoFrame.width * previewVideoFrame.width, y: previewVideoFrame.minY + previewVideoFrame.center.y / fullscreenVideoFrame.height * previewVideoFrame.height))
                    self.animationForExpandedVideoSnapshotView = nil
                }
                minimizedVideoTransition.updateFrame(node: minimizedVideoNode, frame: previewVideoFrame)
                minimizedVideoNode.updateLayout(size: previewVideoFrame.size, cornerRadius: interpolate(from: 14.0, to: 24.0, value: self.pictureInPictureTransitionFraction), isOutgoing: minimizedVideoNode === self.outgoingVideoNodeValue, deviceOrientation: mappedDeviceOrientation, isCompactLayout: layout.metrics.widthClass == .compact, transition: minimizedVideoTransition)
                if transition.isAnimated && didAppear {
                    minimizedVideoNode.layer.animateSpring(from: 0.1 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.5)
                }
            }
            
            self.animationForExpandedVideoSnapshotView = nil
        }
        
        let keyTextSize = self.keyButtonNode.frame.size
        transition.updateFrame(node: self.keyButtonNode, frame: CGRect(origin: CGPoint(x: layout.size.width - keyTextSize.width - 10.0, y: topOriginY + 10.0), size: keyTextSize))
        transition.updateAlpha(node: self.keyButtonNode, alpha: overlayAlpha)
        
        if let debugNode = self.debugNode {
            transition.updateFrame(node: debugNode, frame: CGRect(origin: CGPoint(), size: layout.size))
        }
        
        let requestedAspect: CGFloat
        if case .compact = layout.metrics.widthClass, case .compact = layout.metrics.heightClass {
            var isIncomingVideoRotated = false
            var rotationCount = 0
            
            switch mappedDeviceOrientation {
            case .portrait:
                break
            case .landscapeLeft:
                rotationCount += 1
            case .landscapeRight:
                rotationCount += 1
            case .portraitUpsideDown:
                 break
            default:
                break
            }
            
            if rotationCount % 2 != 0 {
                isIncomingVideoRotated = true
            }
            
            if !isIncomingVideoRotated {
                requestedAspect = layout.size.width / layout.size.height
            } else {
                requestedAspect = 0.0
            }
        } else {
            requestedAspect = 0.0
        }
        if self.currentRequestedAspect != requestedAspect {
            self.currentRequestedAspect = requestedAspect
            if !self.sharedContext.immediateExperimentalUISettings.disableVideoAspectScaling {
                self.call.setRequestedVideoAspect(Float(requestedAspect))
            }
        }
    }
    
    @objc func keyPressed() {
        if self.keyPreviewNode.isHidden {
            self.keyButtonNode.isHidden = true
            self.keyPreviewNode.isHidden = false
            self.encryptionKeyTooltipShown = true
            
            let buttonFrame = self.containerNode.convert(self.keyButtonNode.frame, to: keyPreviewNode)
            keyPreviewNode.animateIn(from: buttonFrame, fromNode: self.keyButtonNode, lightStyle: !self.hasVideo)
            
            self.avatarNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false)
            self.avatarNode.layer.animateScale(from: 1.0, to: 0.1, duration: 0.3, removeOnCompletion: false)
        }
        
        self.updateDimVisibility()
    }
    
    @objc func backPressed() {
        if self.hasVideoNodes {
            if let (layout, navigationHeight) = self.validLayout {
                self.pictureInPictureTransitionFraction = 1.0
                self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
            }
        } else {
            self.back?()
        }
    }
    
    @objc private func closePressed() {
        self.animateOut(completion: { [weak self] in
            self?.dismissedInteractively?()
        })
    }
    
    private func dismissKeyPreviewNode() {
        guard !self.keyPreviewNode.isHidden else { return }
        
        let buttonFrame = self.containerNode.convert(self.keyButtonNode.frame, to: self.keyPreviewNode)
        self.keyPreviewNode.animateOut(to: buttonFrame, toNode: self.keyButtonNode, completion: { [weak self] in
            self?.keyButtonNode.isHidden = false
            self?.keyPreviewNode.isHidden = true
        })
        
        self.avatarNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
        self.avatarNode.layer.animateScale(from: 0.1, to: 1.0, duration: 0.3)
        
        self.updateDimVisibility()
    }
    
    private func displayEncryptionKeyTooltip() {
        guard !self.encryptionKeyTooltipShown && self.keyPreviewNode.isHidden else { return }
        
        // TODO: Replace with a localized string
        let tooltipText = "Encryption key of this call"
        let tooltip = TooltipScreen(account: self.account, text: tooltipText, style: .calls(light: !self.hasVideo), icon: .staticLock, location: .point(self.keyButtonNode.frame.offsetBy(dx: 0.0, dy: 6.0), .bottom), shouldDismissOnTouch: { _ in .dismiss(consume: false) })
        self.present?(tooltip)
    }
    
    private var encryptionKeyTooltipShown: Bool {
        get { UserDefaults.standard.bool(forKey: "Telegram.Calls.EncryptionKeyTooltipShown") }
        set { UserDefaults.standard.set(newValue, forKey: "Telegram.Calls.EncryptionKeyTooltipShown") }
    }
    
    private var hasVideoNodes: Bool {
        return self.expandedVideoNode != nil || self.minimizedVideoNode != nil
    }
    
    private var hasVideo: Bool {
        return self.outgoingVideoNodeValue != nil || self.incomingVideoNodeValue != nil
    }
    
    private var debugTapCounter: (Double, Int) = (0.0, 0)
    
    private func areUserActionsDisabledNow() -> Bool {
        return CACurrentMediaTime() < self.disableActionsUntilTimestamp
    }
    
    @objc func tapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            if !self.pictureInPictureTransitionFraction.isZero {
                self.view.window?.endEditing(true)
                
                if let (layout, navigationHeight) = self.validLayout {
                    self.pictureInPictureTransitionFraction = 0.0
                    
                    self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
                }
            } else {
                if self.hasVideoNodes {
                    let point = recognizer.location(in: recognizer.view)
                    if let expandedVideoNode = self.expandedVideoNode, let minimizedVideoNode = self.minimizedVideoNode, minimizedVideoNode.frame.contains(point) {
                        if !self.areUserActionsDisabledNow() {
                            let copyView = minimizedVideoNode.view.snapshotView(afterScreenUpdates: false)
                            copyView?.frame = minimizedVideoNode.frame
                            self.expandedVideoNode = minimizedVideoNode
                            self.minimizedVideoNode = expandedVideoNode
                            if let supernode = expandedVideoNode.supernode {
                                supernode.insertSubnode(expandedVideoNode, aboveSubnode: minimizedVideoNode)
                            }
                            self.disableActionsUntilTimestamp = CACurrentMediaTime() + 0.3
                            if let (layout, navigationBarHeight) = self.validLayout {
                                self.disableAnimationForExpandedVideoOnce = true
                                self.animationForExpandedVideoSnapshotView = copyView
                                self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                            }
                        }
                    } else {
                        var updated = false
                        if let callState = self.callState {
                            switch callState.state {
                            case .active, .connecting, .reconnecting:
                                self.isUIHidden = !self.isUIHidden
                                updated = true
                            default:
                                break
                            }
                        }
                        if updated, let (layout, navigationBarHeight) = self.validLayout {
                            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                        }
                    }
                } else {
                    let point = recognizer.location(in: recognizer.view)
                    if self.statusNode.frame.contains(point) {
                        if self.easyDebugAccess {
                            self.presentDebugNode()
                        } else {
                            let timestamp = CACurrentMediaTime()
                            if self.debugTapCounter.0 < timestamp - 0.75 {
                                self.debugTapCounter.0 = timestamp
                                self.debugTapCounter.1 = 0
                            }
                            
                            if self.debugTapCounter.0 >= timestamp - 0.75 {
                                self.debugTapCounter.0 = timestamp
                                self.debugTapCounter.1 += 1
                            }
                            
                            if self.debugTapCounter.1 >= 10 {
                                self.debugTapCounter.1 = 0
                                
                                self.presentDebugNode()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func presentDebugNode() {
        guard self.debugNode == nil else {
            return
        }
        
        self.forceReportRating = true
        
        let debugNode = CallDebugNode(signal: self.debugInfo)
        debugNode.dismiss = { [weak self] in
            if let strongSelf = self {
                strongSelf.debugNode?.removeFromSupernode()
                strongSelf.debugNode = nil
            }
        }
        self.addSubnode(debugNode)
        self.debugNode = debugNode
        
        if let (layout, navigationBarHeight) = self.validLayout {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
        }
    }
    
    private var minimizedVideoInitialPosition: CGPoint?
    private var minimizedVideoDraggingPosition: CGPoint?
    
    private func nodeLocationForPosition(layout: ContainerViewLayout, position: CGPoint, velocity: CGPoint) -> VideoNodeCorner {
        let layoutInsets = UIEdgeInsets()
        var result = CGPoint()
        if position.x < layout.size.width / 2.0 {
            result.x = 0.0
        } else {
            result.x = 1.0
        }
        if position.y < layoutInsets.top + (layout.size.height - layoutInsets.bottom - layoutInsets.top) / 2.0 {
            result.y = 0.0
        } else {
            result.y = 1.0
        }
        
        let currentPosition = result
        
        let angleEpsilon: CGFloat = 30.0
        var shouldHide = false
        
        if (velocity.x * velocity.x + velocity.y * velocity.y) >= 500.0 * 500.0 {
            let x = velocity.x
            let y = velocity.y
            
            var angle = atan2(y, x) * 180.0 / CGFloat.pi * -1.0
            if angle < 0.0 {
                angle += 360.0
            }
            
            if currentPosition.x.isZero && currentPosition.y.isZero {
                if ((angle > 0 && angle < 90 - angleEpsilon) || angle > 360 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 0.0
                } else if (angle > 180 + angleEpsilon && angle < 270 + angleEpsilon) {
                    result.x = 0.0
                    result.y = 1.0
                } else if (angle > 270 + angleEpsilon && angle < 360 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 1.0
                } else {
                    shouldHide = true
                }
            } else if !currentPosition.x.isZero && currentPosition.y.isZero {
                if (angle > 90 + angleEpsilon && angle < 180 + angleEpsilon) {
                    result.x = 0.0
                    result.y = 0.0
                }
                else if (angle > 270 - angleEpsilon && angle < 360 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 1.0
                }
                else if (angle > 180 + angleEpsilon && angle < 270 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 1.0
                }
                else {
                    shouldHide = true
                }
            } else if currentPosition.x.isZero && !currentPosition.y.isZero {
                if (angle > 90 - angleEpsilon && angle < 180 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 0.0
                }
                else if (angle < angleEpsilon || angle > 270 + angleEpsilon) {
                    result.x = 1.0
                    result.y = 1.0
                }
                else if (angle > angleEpsilon && angle < 90 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 0.0
                }
                else if (!shouldHide) {
                    shouldHide = true
                }
            } else if !currentPosition.x.isZero && !currentPosition.y.isZero {
                if (angle > angleEpsilon && angle < 90 + angleEpsilon) {
                    result.x = 1.0
                    result.y = 0.0
                }
                else if (angle > 180 - angleEpsilon && angle < 270 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 1.0
                }
                else if (angle > 90 + angleEpsilon && angle < 180 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 0.0
                }
                else if (!shouldHide) {
                    shouldHide = true
                }
            }
        }
        
        if result.x.isZero {
            if result.y.isZero {
                return .topLeft
            } else {
                return .bottomLeft
            }
        } else {
            if result.y.isZero {
                return .topRight
            } else {
                return .bottomRight
            }
        }
    }
    
    @objc private func panGesture(_ recognizer: CallPanGestureRecognizer) {
        switch recognizer.state {
            case .began:
                guard let location = recognizer.firstLocation else {
                    return
                }
                if self.pictureInPictureTransitionFraction.isZero, let expandedVideoNode = self.expandedVideoNode, let minimizedVideoNode = self.minimizedVideoNode, minimizedVideoNode.frame.contains(location), expandedVideoNode.frame != minimizedVideoNode.frame {
                    self.minimizedVideoInitialPosition = minimizedVideoNode.position
                } else if self.hasVideoNodes {
                    self.minimizedVideoInitialPosition = nil
                    if !self.pictureInPictureTransitionFraction.isZero {
                        self.pictureInPictureGestureState = .dragging(initialPosition: self.containerTransformationNode.position, draggingPosition: self.containerTransformationNode.position)
                    } else {
                        self.pictureInPictureGestureState = .collapsing(didSelectCorner: false)
                    }
                } else {
                    self.pictureInPictureGestureState = .none
                }
                self.dismissAllTooltips?()
            case .changed:
                if let minimizedVideoNode = self.minimizedVideoNode, let minimizedVideoInitialPosition = self.minimizedVideoInitialPosition {
                    let translation = recognizer.translation(in: self.view)
                    let minimizedVideoDraggingPosition = CGPoint(x: minimizedVideoInitialPosition.x + translation.x, y: minimizedVideoInitialPosition.y + translation.y)
                    self.minimizedVideoDraggingPosition = minimizedVideoDraggingPosition
                    minimizedVideoNode.position = minimizedVideoDraggingPosition
                } else {
                    switch self.pictureInPictureGestureState {
                    case .none:
                        let offset = recognizer.translation(in: self.view).y
                        var bounds = self.bounds
                        bounds.origin.y = -offset
                        self.bounds = bounds
                    case let .collapsing(didSelectCorner):
                        if let (layout, navigationHeight) = self.validLayout {
                            let offset = recognizer.translation(in: self.view)
                            if !didSelectCorner {
                                self.pictureInPictureGestureState = .collapsing(didSelectCorner: true)
                                if offset.x < 0.0 {
                                    self.pictureInPictureCorner = .topLeft
                                } else {
                                    self.pictureInPictureCorner = .topRight
                                }
                            }
                            let maxOffset: CGFloat = min(300.0, layout.size.height / 2.0)
                            
                            let offsetTransition = max(0.0, min(1.0, abs(offset.y) / maxOffset))
                            self.pictureInPictureTransitionFraction = offsetTransition
                            switch self.pictureInPictureCorner {
                            case .topRight, .bottomRight:
                                self.pictureInPictureCorner = offset.y < 0.0 ? .topRight : .bottomRight
                            case .topLeft, .bottomLeft:
                                self.pictureInPictureCorner = offset.y < 0.0 ? .topLeft : .bottomLeft
                            }
                            
                            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .immediate)
                        }
                    case .dragging(let initialPosition, var draggingPosition):
                        let translation = recognizer.translation(in: self.view)
                        draggingPosition.x = initialPosition.x + translation.x
                        draggingPosition.y = initialPosition.y + translation.y
                        self.pictureInPictureGestureState = .dragging(initialPosition: initialPosition, draggingPosition: draggingPosition)
                        self.containerTransformationNode.position = draggingPosition
                    }
                }
            case .cancelled, .ended:
                if let minimizedVideoNode = self.minimizedVideoNode, let _ = self.minimizedVideoInitialPosition, let minimizedVideoDraggingPosition = self.minimizedVideoDraggingPosition {
                    self.minimizedVideoInitialPosition = nil
                    self.minimizedVideoDraggingPosition = nil
                    
                    if let (layout, navigationHeight) = self.validLayout {
                        self.outgoingVideoNodeCorner = self.nodeLocationForPosition(layout: layout, position: minimizedVideoDraggingPosition, velocity: recognizer.velocity(in: self.view))
                        
                        let videoFrame = self.calculatePreviewVideoRect(layout: layout, navigationHeight: navigationHeight)
                        minimizedVideoNode.frame = videoFrame
                        minimizedVideoNode.layer.animateSpring(from: NSValue(cgPoint: CGPoint(x: minimizedVideoDraggingPosition.x - videoFrame.midX, y: minimizedVideoDraggingPosition.y - videoFrame.midY)), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: 0.5, delay: 0.0, initialVelocity: 0.0, damping: 110.0, removeOnCompletion: true, additive: true, completion: nil)
                    }
                } else {
                    switch self.pictureInPictureGestureState {
                    case .none:
                        let velocity = recognizer.velocity(in: self.view).y
                        if abs(velocity) < 100.0 {
                            var bounds = self.bounds
                            let previous = bounds
                            bounds.origin = CGPoint()
                            self.bounds = bounds
                            self.layer.animateBounds(from: previous, to: bounds, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)
                        } else {
                            var bounds = self.bounds
                            let previous = bounds
                            bounds.origin = CGPoint(x: 0.0, y: velocity > 0.0 ? -bounds.height: bounds.height)
                            self.bounds = bounds
                            self.layer.animateBounds(from: previous, to: bounds, duration: 0.15, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, completion: { [weak self] _ in
                                self?.dismissedInteractively?()
                            })
                        }
                    case .collapsing:
                        self.pictureInPictureGestureState = .none
                        let velocity = recognizer.velocity(in: self.view).y
                        if abs(velocity) < 100.0 && self.pictureInPictureTransitionFraction < 0.5 {
                            if let (layout, navigationHeight) = self.validLayout {
                                self.pictureInPictureTransitionFraction = 0.0
                                
                                self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
                            }
                        } else {
                            if let (layout, navigationHeight) = self.validLayout {
                                self.pictureInPictureTransitionFraction = 1.0
                                
                                self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
                            }
                        }
                    case let .dragging(initialPosition, _):
                        self.pictureInPictureGestureState = .none
                        if let (layout, navigationHeight) = self.validLayout {
                            let translation = recognizer.translation(in: self.view)
                            let draggingPosition = CGPoint(x: initialPosition.x + translation.x, y: initialPosition.y + translation.y)
                            self.pictureInPictureCorner = self.nodeLocationForPosition(layout: layout, position: draggingPosition, velocity: recognizer.velocity(in: self.view))
                            
                            let containerFrame = self.calculatePictureInPictureContainerRect(layout: layout, navigationHeight: navigationHeight)
                            self.containerTransformationNode.frame = containerFrame
                            containerTransformationNode.layer.animateSpring(from: NSValue(cgPoint: CGPoint(x: draggingPosition.x - containerFrame.midX, y: draggingPosition.y - containerFrame.midY)), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: 0.5, delay: 0.0, initialVelocity: 0.0, damping: 110.0, removeOnCompletion: true, additive: true, completion: nil)
                        }
                    }
                }
            default:
                break
        }
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.debugNode != nil {
            return super.hitTest(point, with: event)
        }
        if self.containerTransformationNode.frame.contains(point) {
            return self.containerTransformationNode.view.hitTest(self.view.convert(point, to: self.containerTransformationNode.view), with: event)
        }
        return nil
    }
}

final class CallPanGestureRecognizer: UIPanGestureRecognizer {
    private(set) var firstLocation: CGPoint?
    
    public var shouldBegin: ((CGPoint) -> Bool)?
    
    override public init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        
        self.maximumNumberOfTouches = 1
    }
    
    override public func reset() {
        super.reset()
        
        self.firstLocation = nil
    }
    
    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        
        let touch = touches.first!
        let point = touch.location(in: self.view)
        if let shouldBegin = self.shouldBegin, !shouldBegin(point) {
            self.state = .failed
            return
        }
        
        self.firstLocation = point
    }
    
    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
    }
}
