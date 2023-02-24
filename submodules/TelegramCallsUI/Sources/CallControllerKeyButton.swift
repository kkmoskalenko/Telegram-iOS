import AccountContext
import AnimatedStickerNode
import AsyncDisplayKit
import Display
import ShimmerEffect
import SwiftSignalKit
import TelegramAnimatedStickerNode
import TelegramCore

final class EmojiSlotNode: ASDisplayNode {
    
    enum Content {
        case emoji(String)
        case animatedEmoji(Account, StickerPackItem)
    }
    
    static func updateNodes(_ nodes: [EmojiSlotNode], key: String, accountContext: AccountContext) {
        let key = String(key.prefix(4))
        let animatedKey = key.compactMap { emoji in
            accountContext.animatedEmojiStickers[String(emoji)]?.first
        }
        
        if animatedKey.count == key.count {
            for (node, sticker) in zip(nodes, animatedKey) {
                node.content = .animatedEmoji(accountContext.account, sticker)
            }
        } else {
            for (node, emoji) in zip(nodes, key) {
                node.content = .emoji(String(emoji))
            }
        }
    }
    
    var content: Content = .emoji("") {
        didSet {
            switch self.content {
            case .emoji(let emoji):
                self.textNode.isHidden = false
                self.stickerNode.isHidden = true
                self.stickerNode.visibility = false
                self.placeholderNode.isHidden = true
                
                self.textNode.attributedText = NSAttributedString(string: emoji, font: Font.regular(41.0), textColor: .black, paragraphAlignment: .center)
                let _ = self.textNode.updateLayout(CGSize(width: 100.0, height: 100.0))
            case .animatedEmoji(let account, let stickerPackItem):
                self.textNode.isHidden = true
                self.stickerNode.isHidden = false
                self.stickerNode.visibility = true
                self.placeholderNode.isHidden = false
                self.placeholderNode.alpha = 1.0
                
                let file = stickerPackItem.file
                let source = AnimatedStickerResourceSource(account: account, resource: file.resource)
                self.stickerFetchedDisposable.set(fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .other, userContentType: .sticker, reference: MediaResourceReference.media(media: .standalone(media: file), resource: file.resource)).start())
                
                self.stickerNode.setup(source: source, width: 48 * Int(UIScreenScale), height: 48 * Int(UIScreenScale), playbackMode: .still(.start), mode: .direct(cachePathPrefix: nil))
                self.stickerNode.autoplay = true
                self.stickerNode.playToCompletionOnStop = true
                self.stickerNode.started = { [weak self] in
                    self?.placeholderNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, completion: { [weak self] _ in self?.placeholderNode.isHidden = true })
                }
                
                let placeholderSize = CGSize(width: 48.0, height: 48.0)
                self.placeholderNode.update(backgroundColor: nil, foregroundColor: UIColor(white: 1.0, alpha: 0.2), shimmeringColor: UIColor(white: 1.0, alpha: 0.3), data: file.immediateThumbnailData, size: placeholderSize)
            }
        }
    }
    
    func playOnce() {
        if case .animatedEmoji = self.content {
            self.stickerNode.playOnce()
        }
    }
    
    func stop() {
        if case .animatedEmoji = self.content {
            self.stickerNode.stop()
        }
    }
    
    private let textNode: ImmediateTextNode
    private let stickerNode: AnimatedStickerNode
    private let placeholderNode: StickerShimmerEffectNode
    
    private let stickerFetchedDisposable = MetaDisposable()
    
    override init() {
        self.textNode = ImmediateTextNode()
        self.stickerNode = DefaultAnimatedStickerNodeImpl()
        self.placeholderNode = StickerShimmerEffectNode()
                    
        super.init()
        
        self.addSubnode(self.textNode)
        self.addSubnode(self.stickerNode)
        self.addSubnode(self.placeholderNode)
    }
    
    deinit {
        self.stickerFetchedDisposable.dispose()
    }
    
    override func measure(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: 48.0, height: 48.0)
    }
    
    override func layout() {
        super.layout()
        
        self.textNode.frame = self.bounds
        self.stickerNode.frame = self.bounds
        self.stickerNode.updateLayout(size: self.bounds.size)
        self.placeholderNode.frame = self.bounds
        self.placeholderNode.updateAbsoluteRect(self.bounds, within: self.bounds.size)
    }
}

final class CallControllerKeyButton: HighlightableButtonNode {
    private let accountContext: AccountContext
    private let containerNode: ASDisplayNode
    private let nodes: [EmojiSlotNode]
    
    var key: String = "" {
        didSet {
            guard self.key != oldValue else { return }
            EmojiSlotNode.updateNodes(self.nodes, key: self.key, accountContext: self.accountContext)
        }
    }
    
    init(accountContext: AccountContext) {
        self.accountContext = accountContext
        self.containerNode = ASDisplayNode()
        self.nodes = (0 ..< 4).map { _ in EmojiSlotNode() }
       
        super.init(pointerStyle: nil)
        
        self.addSubnode(self.containerNode)
        self.nodes.forEach({ self.containerNode.addSubnode($0) })
    }
        
    func animateIn() {
        self.layoutIfNeeded()
        self.containerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
    }
    
    override func measure(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: 105.0, height: 24.0)
    }
    
    override func layout() {
        super.layout()
        
        self.containerNode.frame = self.bounds
        var index = 0
        let nodeSize = CGSize(width: 48.0, height: 2.0 * self.bounds.size.height)
        for node in self.nodes {
            node.anchorPoint = CGPoint(x: 0.0, y: 0.0)
            node.transform = CATransform3DMakeScale(0.5, 0.5, 1.0)
            node.frame = CGRect(origin: CGPoint(x: CGFloat(index) * (3.0 + nodeSize.width / 2.0), y: 0.0), size: nodeSize)
            index += 1
        }
        self.nodes.forEach({ self.containerNode.addSubnode($0) })
    }
}
