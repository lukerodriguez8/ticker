import AppKit

@MainActor
final class TextStrip: NSView {
    var text = "" { didSet { needsDisplay = true } }
    var offset: CGFloat = 0 { didSet { needsDisplay = true } }
    var loopDistance: CGFloat = 0 { didSet { needsDisplay = true } }

    var attributed: NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.menuBarFont(ofSize: 0),
                                                      .foregroundColor: NSColor.labelColor])
    }

    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath(rect: bounds).addClip()  // no implicit clipping on macOS 14+
        let line = attributed
        let y = floor((bounds.height - line.size().height) / 2)
        line.draw(at: NSPoint(x: -offset, y: y))
        if loopDistance > 0 { line.draw(at: NSPoint(x: loopDistance - offset, y: y)) }
    }
}

@MainActor
final class MarqueeView: NSView {
    enum Zone { case like, dislike, body }

    private let icon = NSImageView()
    private let strip = TextStrip()
    private let up = NSImageView()
    private let down = NSImageView()
    private let thumbWidth: CGFloat = 15
    private let thumbGap: CGFloat = 7
    private let iconWidth: CGFloat = 16
    private let iconGap: CGFloat = 5
    private let loopGap: CGFloat = 48
    private let speed: CGFloat = 38  // points per second
    private let fps: Double = 30
    private let pause: TimeInterval = 3
    private var pauseUntil = Date()

    var loopDuration: TimeInterval {
        strip.loopDistance > 0 ? pause + TimeInterval(strip.loopDistance / speed) : 0
    }
    private var timer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        for view in [icon, up, down] {
            view.imageScaling = .scaleProportionallyDown
            addSubview(view)
        }
        addSubview(strip)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // pass clicks through to the button
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func set(text: String, image: NSImage?, rating: Int?, maxTextWidth: CGFloat, height: CGFloat) -> CGFloat {
        icon.image = image
        setRating(rating)
        strip.text = text
        let textWidth = ceil(strip.attributed.size().width)
        let visible = min(textWidth, maxTextWidth)
        let thumbsX = 4 + iconWidth + iconGap + visible + 12
        let total = thumbsX + thumbWidth + thumbGap + thumbWidth + 4

        frame = NSRect(x: 0, y: 0, width: total, height: height)
        icon.frame = NSRect(x: 4, y: (height - iconWidth) / 2, width: iconWidth, height: iconWidth)
        strip.frame = NSRect(x: 4 + iconWidth + iconGap, y: 0, width: visible, height: height)
        up.frame = NSRect(x: thumbsX, y: (height - thumbWidth) / 2, width: thumbWidth, height: thumbWidth)
        down.frame = NSRect(x: thumbsX + thumbWidth + thumbGap, y: (height - thumbWidth) / 2,
                            width: thumbWidth, height: thumbWidth)
        strip.offset = 0
        strip.loopDistance = textWidth > maxTextWidth ? textWidth + loopGap : 0

        timer?.invalidate()
        timer = nil
        if strip.loopDistance > 0 {
            pauseUntil = Date().addingTimeInterval(pause)
            timer = Timer.scheduledTimer(timeInterval: 1 / fps, target: self, selector: #selector(tick),
                                         userInfo: nil, repeats: true)
        }
        return total
    }

    func setRating(_ rating: Int?) {
        up.image = symbol(rating == 1 ? "hand.thumbsup.fill" : "hand.thumbsup", "Like")
        down.image = symbol("hand.thumbsdown", "Dislike and skip")
    }

    func zone(at point: NSPoint) -> Zone {
        if point.x >= down.frame.minX - thumbGap / 2 { return .dislike }
        if point.x >= up.frame.minX - 5 { return .like }
        return .body
    }

    private func symbol(_ name: String, _ label: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        image?.isTemplate = true
        return image
    }

    @objc private func tick() {
        guard Date() >= pauseUntil else { return }
        let next = strip.offset + speed / CGFloat(fps)
        if next >= strip.loopDistance {
            strip.offset = 0
            pauseUntil = Date().addingTimeInterval(pause)
        } else {
            strip.offset = next
        }
    }
}
