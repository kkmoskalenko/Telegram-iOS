import AccountContext
import AsyncDisplayKit
import AvatarNode
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

private let avatarSize = CGSize(width: 136.0, height: 136.0)
private let blobSize = CGSize(width: 200.0, height: 200.0)
private let avatarFont = avatarPlaceholderFont(size: floor(136.0 * 16.0 / 37.0))

final class CallControllerAvatarNode: ASDisplayNode {
    
    private let sharedContext: SharedAccountContext
    private let account: Account
    private var presentationData: PresentationData
    private let call: PresentationCall
    
    private var connectingAnimationTimer: SwiftSignalKit.Timer?
    private var audioLevelDisposable: Disposable?
    
    private lazy var avatarNode: AvatarNode = {
        let avatarNode = AvatarNode(font: avatarFont)
        avatarNode.frame = CGRect(origin: .zero, size: avatarSize)
        return avatarNode
    }()
    
    private lazy var voiceBlobView: VoiceBlobView = {
        let blobOrigin = CGPoint(x: (avatarSize.width - blobSize.width) / 2.0, y: (avatarSize.height - blobSize.height) / 2.0)
        let blobView = VoiceBlobView(frame: CGRect(origin: blobOrigin, size: blobSize), maxLevel: 1.5, mediumBlobRange: (0.79, 0.92), bigBlobRange: (0.86, 1.0))
        blobView.setColor(.white)
        return blobView
    }()
    
    init(sharedContext: SharedAccountContext, account: Account, presentationData: PresentationData, call: PresentationCall) {
        self.sharedContext = sharedContext
        self.account = account
        self.presentationData = presentationData
        self.call = call
        
        super.init()
        
        self.view.addSubview(self.voiceBlobView)
        self.addSubnode(self.avatarNode)
        
        self.audioLevelDisposable = (call.audioLevel
        |> deliverOnMainQueue).start(next: { [weak self] level in
            self?.voiceBlobView.updateLevel(CGFloat(level), immediately: false)
        })
    }
    
    deinit {
        self.connectingAnimationTimer?.invalidate()
        self.audioLevelDisposable?.dispose()
    }
    
    func setPeer(_ peer: Peer) {
        self.avatarNode.setPeer(context: self.call.context, account: self.account, theme: self.presentationData.theme, peer: EnginePeer(peer), displayDimensions: avatarSize)
    }
    
    func playConnectingAnimation() {
        guard self.connectingAnimationTimer == nil else { return }
        
        self.connectingAnimationTimer = SwiftSignalKit.Timer(timeout: 2.0, repeat: true, completion: { [weak self] in
            self?.layer.animateScale(from: 1.0, to: 1.05, duration: 2.0/3.0, removeOnCompletion: false) { [weak self] _ in
                self?.layer.animateScale(from: 1.05, to: 1.0, duration: 2.0/3.0, delay: 1.0/3.0, removeOnCompletion: false)
            }
        }, queue: .mainQueue())
        self.connectingAnimationTimer?.start()
    }
    
    func playConnectedAnimation() {
        self.connectingAnimationTimer?.invalidate()
        self.connectingAnimationTimer = nil
        
        let stageDuration: Double = 1.0 / 6.0
        let avatarScale = self.avatarNode.layer.value(forKeyPath: "transform.scale.x") as? CGFloat ?? 1.0
        
        self.voiceBlobView.layer.animateScale(from: 1.0, to: 1.35, duration: stageDuration, removeOnCompletion: false)
        self.avatarNode.layer.animateScale(from: avatarScale, to: 1.1, duration: stageDuration, removeOnCompletion: false) { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.voiceBlobView.layer.animateScale(from: 1.35, to: 1.0, duration: stageDuration, removeOnCompletion: false)
            strongSelf.avatarNode.layer.animateScale(from: 1.1, to: 0.95, duration: stageDuration, removeOnCompletion: false) { [weak self] _ in
                guard let strongSelf = self else { return }
                strongSelf.avatarNode.layer.animateScale(from: 0.95, to: 1.0, duration: stageDuration, removeOnCompletion: false)
            }
        }
    }
    
    func playMuteAnimation() {
        guard !self.voiceBlobView.isHidden else { return }
        
        if self.connectingAnimationTimer != nil {
            self.connectingAnimationTimer?.invalidate()
            self.connectingAnimationTimer = nil
            
            let avatarScale = self.avatarNode.layer.value(forKeyPath: "transform.scale.x") as? CGFloat ?? 1.0
            self.avatarNode.layer.animateScale(from: avatarScale, to: 1.0, duration: 0.25, removeOnCompletion: false)
        }
        
        self.voiceBlobView.layer.animateScale(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false) { [weak self] _ in
            self?.voiceBlobView.isHidden = true
            self?.voiceBlobView.stopAnimating()
            self?.voiceBlobView.layer.removeAllAnimations()
        }
    }
    
    func playUnmuteAnimation() {
        guard self.voiceBlobView.isHidden else { return }
        
        self.voiceBlobView.isHidden = false
        self.voiceBlobView.startAnimating()
        self.voiceBlobView.layer.animateSpring(from: 0.1 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.45, removeOnCompletion: false)
    }
    
    override public func didEnterHierarchy() {
        super.didEnterHierarchy()
        self.voiceBlobView.startAnimating()
    }
    
    override public func didExitHierarchy() {
        super.didExitHierarchy()
        self.voiceBlobView.stopAnimating()
    }
}

private final class VoiceBlobView: UIView {
    private let mediumBlob: BlobView
    private let bigBlob: BlobView
    
    private let maxLevel: CGFloat
    
    private var displayLinkAnimator: ConstantDisplayLinkAnimator?
    
    private var audioLevel: CGFloat = 0.0
    var presentationAudioLevel: CGFloat = 0.0
    
    var scaleUpdated: ((CGFloat) -> Void)? {
        didSet {
            self.bigBlob.scaleUpdated = self.scaleUpdated
        }
    }
    
    private(set) var isAnimating = false
    
    public typealias BlobRange = (min: CGFloat, max: CGFloat)

    private let hierarchyTrackingNode: HierarchyTrackingNode
    private var isCurrentlyInHierarchy = true
    
    public init(
        frame: CGRect,
        maxLevel: CGFloat,
        mediumBlobRange: BlobRange,
        bigBlobRange: BlobRange
    ) {
        var updateInHierarchy: ((Bool) -> Void)?
        self.hierarchyTrackingNode = HierarchyTrackingNode({ value in
            updateInHierarchy?(value)
        })
        
        self.maxLevel = maxLevel
        
        self.mediumBlob = BlobView(
            pointsCount: 8,
            minRandomness: 1,
            maxRandomness: 1,
            minSpeed: 0.9,
            maxSpeed: 4.0,
            minScale: mediumBlobRange.min,
            maxScale: mediumBlobRange.max
        )
        self.bigBlob = BlobView(
            pointsCount: 8,
            minRandomness: 1,
            maxRandomness: 1,
            minSpeed: 1.0,
            maxSpeed: 4.4,
            minScale: bigBlobRange.min,
            maxScale: bigBlobRange.max
        )
        
        super.init(frame: frame)

        addSubnode(hierarchyTrackingNode)
        
        addSubview(bigBlob)
        addSubview(mediumBlob)
        
        displayLinkAnimator = ConstantDisplayLinkAnimator() { [weak self] in
            guard let strongSelf = self else { return }

            if !strongSelf.isCurrentlyInHierarchy {
                return
            }
            
            strongSelf.presentationAudioLevel = strongSelf.presentationAudioLevel * 0.9 + strongSelf.audioLevel * 0.1
            
            strongSelf.mediumBlob.level = strongSelf.presentationAudioLevel
            strongSelf.bigBlob.level = strongSelf.presentationAudioLevel
        }

        updateInHierarchy = { [weak self] value in
            if let strongSelf = self {
                strongSelf.isCurrentlyInHierarchy = value
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setColor(_ color: UIColor) {
        mediumBlob.setColor(color.withAlphaComponent(0.2))
        bigBlob.setColor(color.withAlphaComponent(0.1))
    }
    
    public func updateLevel(_ level: CGFloat, immediately: Bool) {
        let normalizedLevel = min(1, max(level / maxLevel, 0))
        
        mediumBlob.updateSpeedLevel(to: normalizedLevel)
        bigBlob.updateSpeedLevel(to: normalizedLevel)
        
        audioLevel = normalizedLevel
        if immediately {
            presentationAudioLevel = normalizedLevel
        }
    }
    
    public func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        
        updateBlobsState()
        
        displayLinkAnimator?.isPaused = false
    }
    
    public func stopAnimating() {
        self.stopAnimating(duration: 0.15)
    }
    
    public func stopAnimating(duration: Double) {
        guard isAnimating else { return }
        isAnimating = false
        
        updateBlobsState()
        
        displayLinkAnimator?.isPaused = true
    }
    
    private func updateBlobsState() {
        if isAnimating {
            if mediumBlob.frame.size != .zero {
                mediumBlob.startAnimating()
                bigBlob.startAnimating()
            }
        } else {
            mediumBlob.stopAnimating()
            bigBlob.stopAnimating()
        }
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        
        mediumBlob.frame = bounds
        bigBlob.frame = bounds
        
        updateBlobsState()
    }
}
