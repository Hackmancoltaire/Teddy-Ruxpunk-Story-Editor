import Cocoa
import AVFoundation
import Accelerate

class WaveformView: NSView {
	override var isOpaque: Bool { true }

	// Raw audio samples cached in memory (left channel only)
	private var cachedBuffer: [Float]?
	private var sampleRate: Double = 44100

	// Rendering parameters (set by controller on scroll/zoom)
	var displayOffset: Int = 0
	var pixelsPerSecond: CGFloat = 100

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

	/// Async load: reads entire left channel into memory, then renders visible portion
	func load(_ url: URL) {
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			guard let file = try? AVAudioFile(forReading: url) else { return }
			let buffer = Self.readEntireLeftChannel(file: file)
			let sr = file.processingFormat.sampleRate
			DispatchQueue.main.async {
				self?.cachedBuffer = buffer
				self?.sampleRate = sr
				self?.renderVisibleContent()
			}
		}
	}

	/// Called by controller on scroll or zoom — updates params and re-renders viewport
	func updateDisplay(offset: Int, pixelsPerSecond pps: CGFloat) {
		displayOffset = offset
		pixelsPerSecond = pps
		renderVisibleContent()
	}

	/// Renders only the visible viewport (~960px) from the cached audio buffer
	private func renderVisibleContent() {
		guard let buffer = cachedBuffer, !buffer.isEmpty else {
			layer?.contents = nil
			return
		}

		let w = Int(ceil(bounds.width))
		let h = Int(ceil(bounds.height))
		guard w > 0, h > 0 else { return }

		let samplesPerPixel = sampleRate / Double(pixelsPerSecond)
		let totalPixels = Int(Double(buffer.count) / samplesPerPixel)

		// Compute peaks for just the visible pixel range
		var visiblePeaks: [(min: Float, max: Float)] = []
		visiblePeaks.reserveCapacity(w)

		for px in 0..<w {
			let globalPx = displayOffset + px
			guard globalPx < totalPixels else { break }

			let sampleStart = Int(Double(globalPx) * samplesPerPixel)
			let sampleEnd = min(sampleStart + Int(ceil(samplesPerPixel)), buffer.count)
			let count = sampleEnd - sampleStart
			guard count > 0 else {
				visiblePeaks.append((min: 0, max: 0))
				continue
			}

			var lo: Float = 0, hi: Float = 0
			buffer.withUnsafeBufferPointer { ptr in
				vDSP_minv(ptr.baseAddress! + sampleStart, 1, &lo, vDSP_Length(count))
				vDSP_maxv(ptr.baseAddress! + sampleStart, 1, &hi, vDSP_Length(count))
			}
			visiblePeaks.append((min: lo, max: hi))
		}

		guard !visiblePeaks.isEmpty else { layer?.contents = nil; return }

		// Render to viewport-sized image
		let image = NSImage(size: NSSize(width: w, height: h))
		image.lockFocus()

		NSColor.black.setFill()
		NSRect(x: 0, y: 0, width: w, height: h).fill()

		let mid = CGFloat(h) / 2
		let path = NSBezierPath()
		path.move(to: NSPoint(x: 0, y: mid + CGFloat(visiblePeaks[0].max) * mid))
		for (i, p) in visiblePeaks.enumerated() {
			path.line(to: NSPoint(x: CGFloat(i), y: mid + CGFloat(p.max) * mid))
		}
		for (i, p) in visiblePeaks.enumerated().reversed() {
			path.line(to: NSPoint(x: CGFloat(i), y: mid + CGFloat(p.min) * mid))
		}
		path.close()

		NSColor.systemGreen.setFill()
		path.fill()

		image.unlockFocus()

		CATransaction.begin()
		CATransaction.setDisableActions(true)
		layer?.contents = image
		CATransaction.commit()
	}

	private static func readEntireLeftChannel(file: AVAudioFile) -> [Float] {
		let totalFrames = Int(file.length)
		let format = file.processingFormat
		let chunkSize: AVAudioFrameCount = 65536
		guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
			return []
		}

		file.framePosition = 0
		var result: [Float] = []
		result.reserveCapacity(totalFrames)

		while file.framePosition < file.length {
			buffer.frameLength = 0
			do { try file.read(into: buffer, frameCount: chunkSize) } catch { break }

			let n = Int(buffer.frameLength)
			guard n > 0, let channels = buffer.floatChannelData else { break }

			let channelData = channels[0]
			result.append(contentsOf: UnsafeBufferPointer(start: channelData, count: n))
		}
		return result
	}
}
