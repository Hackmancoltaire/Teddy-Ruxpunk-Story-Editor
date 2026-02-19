import Cocoa

// MARK: - ParameterWaveformView (Timeline Step Graph)

class ParameterWaveformView: NSView {
	override var isOpaque: Bool { true }

	private var label: String = ""
	private var color: NSColor = .systemGreen
	private var maxValue: CGFloat = 1.0

	// Sparse analysis data (normalized 0..1 positions + raw values)
	private var cachedPoints: [(normalizedX: CGFloat, rawValue: CGFloat)] = []

	// Rendering parameters (set by controller on scroll/zoom)
	var displayOffset: Int = 0
	var totalTimelineWidth: Int = 0

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layerContentsRedrawPolicy = .never
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		wantsLayer = true
		layerContentsRedrawPolicy = .never
	}

	func configure(label: String, color: NSColor, maxValue: CGFloat) {
		self.label = label
		self.color = color
		self.maxValue = maxValue
	}

	/// Stores sparse analysis points. Call updateDisplay() afterwards to render.
	func loadTimeline(points: [(normalizedX: CGFloat, rawValue: CGFloat)]) {
		cachedPoints = points
	}

	/// Called by controller on scroll or zoom — updates params and re-renders viewport
	func updateDisplay(offset: Int, timelineWidth: Int) {
		displayOffset = offset
		totalTimelineWidth = timelineWidth
		renderVisibleContent()
	}

	/// Renders only the visible viewport from sparse analysis data
	private func renderVisibleContent() {
		let w = Int(ceil(bounds.width))
		let h = Int(ceil(bounds.height))
		guard w > 0, h > 0, totalTimelineWidth > 0 else {
			layer?.contents = nil
			return
		}

		let image = NSImage(size: NSSize(width: w, height: h))
		image.lockFocus()

		// Background
		NSColor.black.setFill()
		NSRect(x: 0, y: 0, width: w, height: h).fill()

		if !cachedPoints.isEmpty && maxValue > 0 {
			let fh = CGFloat(h)
			let tw = CGFloat(totalTimelineWidth)

			// Find the initial value at the left edge (last point before displayOffset)
			var currentVal: CGFloat = 0
			for p in cachedPoints {
				let px = p.normalizedX * tw
				if px <= CGFloat(displayOffset) {
					currentVal = min(max(p.rawValue / maxValue, 0), 1)
				} else {
					break
				}
			}

			// Build step profile in viewport coordinates
			var profile: [(x: CGFloat, y: CGFloat)] = []
			profile.append((x: 0, y: currentVal * fh))

			for p in cachedPoints {
				let px = p.normalizedX * tw
				let localX = px - CGFloat(displayOffset)
				if localX < 0 { continue }
				if localX > CGFloat(w) { break }

				let newVal = min(max(p.rawValue / maxValue, 0), 1)
				let lastY = profile.last?.y ?? 0
				profile.append((x: localX, y: lastY))
				profile.append((x: localX, y: newVal * fh))
			}

			let lastY = profile.last?.y ?? 0
			profile.append((x: CGFloat(w), y: lastY))

			// Fill path
			let fillPath = NSBezierPath()
			fillPath.move(to: NSPoint(x: profile[0].x, y: 0))
			for pt in profile {
				fillPath.line(to: NSPoint(x: pt.x, y: pt.y))
			}
			fillPath.line(to: NSPoint(x: CGFloat(w), y: 0))
			fillPath.close()

			color.withAlphaComponent(0.3).setFill()
			fillPath.fill()

			// Stroke top edge
			let strokePath = NSBezierPath()
			strokePath.lineWidth = 1.0
			strokePath.move(to: NSPoint(x: profile[0].x, y: profile[0].y))
			for i in 1..<profile.count {
				strokePath.line(to: NSPoint(x: profile[i].x, y: profile[i].y))
			}
			color.setStroke()
			strokePath.stroke()
		}

		// Label (always at top-left of viewport — stays pinned on scroll)
		if !label.isEmpty {
			let attrs: [NSAttributedString.Key: Any] = [
				.foregroundColor: NSColor.white,
				.font: NSFont.systemFont(ofSize: 10, weight: .medium)
			]
			let str = NSAttributedString(string: "\(label) (0-\(Int(maxValue)))", attributes: attrs)
			str.draw(at: NSPoint(x: 4, y: CGFloat(h) - 14))
		}

		image.unlockFocus()

		CATransaction.begin()
		CATransaction.setDisableActions(true)
		layer?.contents = image
		CATransaction.commit()
	}
}

// MARK: - TimelineContainerView

class TimelineContainerView: NSView {
	override var isFlipped: Bool { true }

	var onSeek: ((CGFloat) -> Void)?

	override func mouseDown(with event: NSEvent) {
		handleSeek(with: event)
	}

	override func mouseDragged(with event: NSEvent) {
		handleSeek(with: event)
	}

	private func handleSeek(with event: NSEvent) {
		let localPoint = convert(event.locationInWindow, from: nil)
		let width = bounds.width
		guard width > 0 else { return }
		let normalized = (localPoint.x / width).clamped(to: 0...1)
		onSeek?(normalized)
	}

	override func resetCursorRects() {
		addCursorRect(bounds, cursor: .crosshair)
	}
}

// MARK: - PlayheadView

class PlayheadView: NSView {
	override var isOpaque: Bool { false }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = NSColor.white.cgColor
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		wantsLayer = true
		layer?.backgroundColor = NSColor.white.cgColor
	}
}
