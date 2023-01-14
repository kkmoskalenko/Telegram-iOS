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
    
    private let titleView: FadeTruncatingLabel
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
        self.titleView = FadeTruncatingLabel()
        self.infoNode = ChatTitleActivityNode()
        
        self.recordingIconNode = VoiceChatRecordingIconNode(hasBackground: false)
        
        self.liveIndicatorNode = VoiceChatLiveIndicatorNode()
        self.liveIndicatorNode.isHidden = true
        
        super.init()
        
        self.view.addSubview(self.titleView)
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
        if point.y > 0.0 && point.y < self.frame.size.height && point.x > min(self.titleView.frame.minX, self.infoNode.frame.minX) && point.x < max(self.recordingIconNode.frame.maxX, self.infoNode.frame.maxX) {
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
        if let previousTitle = self.titleView.attributedText?.string {
            titleUpdated = previousTitle != title
        }
        
        if titleUpdated, let snapshotView = self.titleView.snapshotView(afterScreenUpdates: false) {
            snapshotView.frame = self.titleView.frame
            self.view.addSubview(snapshotView)
            
            snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                snapshotView?.removeFromSuperview()
            })
            
            self.titleView.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
            
            if slide {
                self.infoNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                let offset: CGFloat = 16.0
                snapshotView.layer.animatePosition(from: CGPoint(), to: CGPoint(x: 0.0, y: -offset), duration: 0.2, removeOnCompletion: false, additive: true)
                self.titleView.layer.animatePosition(from: CGPoint(x: 0.0, y: offset), to: CGPoint(), duration: 0.2, additive: true)
                self.infoNode.layer.animatePosition(from: CGPoint(x: 0.0, y: offset), to: CGPoint(), duration: 0.2, additive: true)
            }
        }
        
        self.titleView.attributedText = NSAttributedString(string: title, font: Font.medium(17.0), textColor: UIColor(rgb: 0xffffff))
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
        let titleSize = self.titleView.sizeThatFits(constrainedSize)
        let infoSize = self.infoNode.updateLayout(constrainedSize, offset: 1.0, alignment: .center)
        let titleInfoSpacing: CGFloat = 0.0
        
        let combinedHeight = titleSize.height + infoSize.height + titleInfoSpacing
        
        let titleFrame = CGRect(origin: CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: floor((size.height - combinedHeight) / 2.0)), size: titleSize)
        self.titleView.frame = titleFrame
        self.infoNode.frame = CGRect(origin: CGPoint(x: floor((size.width - infoSize.width) / 2.0), y: floor((size.height - combinedHeight) / 2.0) + titleSize.height + titleInfoSpacing), size: infoSize)
        
        let iconSide = 16.0 + (1.0 + UIScreenPixel) * 2.0
        let iconSize: CGSize = CGSize(width: iconSide, height: iconSide)
        self.recordingIconNode.frame = CGRect(origin: CGPoint(x: titleFrame.maxX + 2.0, y: titleFrame.minY + 2.0), size: iconSize)
    }
    
    func update(size: CGSize, title: String) {
        guard !size.width.isZero else { return }
        
        self.titleView.attributedText = NSAttributedString(string: title, font: Font.medium(17.0), textColor: UIColor(rgb: 0xffffff))
        self.infoNode.isHidden = true
        self.liveIndicatorNode.isHidden = false
        
        let constrainedSize = CGSize(width: size.width - 181.0, height: size.height)
        let titleSize = self.titleView.sizeThatFits(constrainedSize)
        let indicatorSize = CGSize(width: 35.0, height: 20.0)
        let indicatorOffset: CGFloat = 7.0
        
        let titleFrame = CGRect(origin: CGPoint(x: floor((size.width - titleSize.width - indicatorSize.width - indicatorOffset) / 2.0), y: floor((size.height - titleSize.height) / 2.0)), size: titleSize)
        let indicatorFrame = CGRect(origin: CGPoint(x: titleFrame.maxX + indicatorOffset, y: titleFrame.minY), size: indicatorSize)
        
        self.titleView.frame = titleFrame
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

// MARK: - Fade Truncating Label

private final class FadeTruncatingLabel: UIView {
    
    var attributedText: NSAttributedString? {
        didSet {
            setNeedsLayout()
        }
    }
    
    private(set) var isTruncated: Bool = false
    
    private var textLine: CTLine?
    private var textBounds: CGRect?
    
    // MARK: Initializers
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Size Calculation
    
    override var intrinsicContentSize: CGSize {
        textBounds?.size ?? super.intrinsicContentSize
    }
    
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let attributedString = attributedText else { return super.sizeThatFits(size) }
        let line = CTLineCreateWithAttributedString(attributedString)
        let truncatedLine = CTLineCreateTruncatedLine(line, size.width, .end, nil)
        return (truncatedLine ?? line).typographicBounds().size
    }
    
    override func layoutSubviews() {
        defer { setNeedsDisplay() }
        super.layoutSubviews()
        
        guard let attributedString = attributedText else {
            textLine = nil
            textBounds = nil
            isTruncated = false
            return
        }
        
        let line = CTLineCreateWithAttributedString(attributedString)
        if let truncatedLine = CTLineCreateTruncatedLine(line, bounds.width, .end, nil) {
            let glyphCount = CTLineGetGlyphCount(line)
            let truncatedGlyphCount = CTLineGetGlyphCount(truncatedLine)
            
            textLine = truncatedLine
            isTruncated = truncatedGlyphCount < glyphCount
        } else {
            textLine = line
            isTruncated = false
        }
        
        textBounds = textLine!.typographicBounds()
        invalidateIntrinsicContentSize()
    }
    
    // MARK: Drawing
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let context = UIGraphicsGetCurrentContext(),
              let line = textLine, let textBounds = textBounds
        else { return }
        
        context.textMatrix = .identity
        context.textPosition = .zero
        
        context.translateBy(x: -textBounds.minX, y: textBounds.maxY)
        context.scaleBy(x: 1.0, y: -1.0)
        
        CTLineDraw(line, context)
        
        if let (truncatedRect, isRTL) = truncatedRegionBounds() {
            var maskingRect = truncatedRect
            maskingRect.origin.y = textBounds.origin.y
            maskingRect.size.height = textBounds.size.height
            
            let maskWidth = min(2 * textBounds.size.height, 0.25 * textBounds.size.width)
            if !isRTL {
                maskingRect.origin.x = maskingRect.maxX - maskWidth
            }
            maskingRect.size.width = maskWidth
            maskingRect = maskingRect.intersection(textBounds)
            maskingRect = maskingRect.insetBy(dx: -UIScreenPixel, dy: -UIScreenPixel)
            
            if let mask = generateMask(size: maskingRect.size, rightToLeft: isRTL) {
                context.clip(to: maskingRect, mask: mask)
                context.clear(maskingRect)
                context.resetClip()
            }
        }
    }
    
    private func truncatedRegionBounds() -> (CGRect, Bool)? {
        guard isTruncated, let line = textLine else { return nil }
        
        let lineRange = CTLineGetStringRange(line)
        let lineUpperBound = lineRange.location + lineRange.length
        
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let runRange = CTRunGetStringRange(run)
            let runUpperBound = runRange.location + runRange.length
            let isRTL = CTRunGetStatus(run).contains(.rightToLeft)
            
            if runUpperBound < lineUpperBound { continue }
            
            // Apparently, `CTRunGetImageBounds` may return incorrect bounds for lines containing right-to-left text.
            // Thus, it was necessary to create a custom implementation that calculates bounds based on glyph bounds.
            return (run.boundingRect(), isRTL)
        }
        
        return nil
    }
    
    private func generateMask(size: CGSize, rightToLeft: Bool) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        
        var locations: [CGFloat] = rightToLeft ? [0.0, 1.0] : [1.0, 0.0]
        let colors: [CGColor] = [UIColor.white, UIColor.black].map(\.cgColor)
        
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as NSArray, locations: &locations)
        else { return nil }
        
        let startPoint = CGPoint(x: .zero, y: size.height / 2.0)
        let endPoint = CGPoint(x: size.width, y: size.height / 2.0)
        context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
        
        return context.makeImage()
    }
}

extension CTLine {
    
    fileprivate func typographicBounds() -> CGRect {
        var ascent: CGFloat = 0.0
        var descent: CGFloat = 0.0
        var leading: CGFloat = 0.0
        let width: CGFloat = CTLineGetTypographicBounds(self, &ascent, &descent, &leading)
        return CGRect(x: 0.0, y: -(descent + leading), width: width, height: ascent + descent + leading)
    }
}

extension CTRun {
    
    fileprivate func boundingRect() -> CGRect {
        let glyphCount = CTRunGetGlyphCount(self)
        
        let attributes: NSDictionary = CTRunGetAttributes(self)
        let font = attributes[kCTFontAttributeName] as! CTFont
        
        let glyphPositions: [CGPoint] = Array(unsafeUninitializedCapacity: glyphCount) { bufferPointer, count in
            CTRunGetPositions(self, CFRange(), bufferPointer.baseAddress!)
            count = glyphCount
        }
        
        let glyphs: [CGGlyph] = Array(unsafeUninitializedCapacity: glyphCount) { bufferPointer, count in
            CTRunGetGlyphs(self, CFRange(), bufferPointer.baseAddress!)
            count = glyphCount
        }
        
        let glyphBoundingRects: [CGRect] = Array(unsafeUninitializedCapacity: glyphCount) { bufferPointer, count in
            CTFontGetBoundingRectsForGlyphs(font, .default, glyphs, bufferPointer.baseAddress!, glyphCount)
            count = glyphCount
        }
        
        var bounds: CGRect = .null
        for glyphIndex in 0 ..< glyphCount {
            let position = glyphPositions[glyphIndex]
            let glyphBounds = glyphBoundingRects[glyphIndex]
                .offsetBy(dx: position.x, dy: position.y)
            bounds = bounds.union(glyphBounds)
        }
        return bounds
    }
}
