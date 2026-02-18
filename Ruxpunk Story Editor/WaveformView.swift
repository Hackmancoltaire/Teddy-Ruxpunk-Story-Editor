import Cocoa
import AVFoundation
import Accelerate

class WaveformView: NSView {
	override var isOpaque: Bool { true }

	private var peaks: [(min: Float, max: Float)] = []

	func load(_ url: URL, peakCount: Int) {
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			guard let file = try? AVAudioFile(forReading: url) else { return }
			let peaks = Self.computePeaks(file: file, count: peakCount)
			DispatchQueue.main.async {
				self?.peaks = peaks
				self?.needsDisplay = true
			}
		}
	}

	private static func computePeaks(file: AVAudioFile, count: Int) -> [(min: Float, max: Float)] {
		let totalFrames = Int(file.length)
		let framesPerPeak = totalFrames / count
		guard framesPerPeak > 0 else { return [] }

		let format = file.processingFormat
		let capacity = AVAudioFrameCount(framesPerPeak)
		guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
			return []
		}

		file.framePosition = 0
		var peaks: [(min: Float, max: Float)] = []
		peaks.reserveCapacity(count)

		for _ in 0..<count {
			buffer.frameLength = 0
			do { try file.read(into: buffer, frameCount: capacity) } catch { break }

			let n = Int(buffer.frameLength)
			guard n > 0, let channels = buffer.floatChannelData else { break }

			var lo: Float = 0, hi: Float = 0
			vDSP_minv(channels[0], 1, &lo, vDSP_Length(n))
			vDSP_maxv(channels[0], 1, &hi, vDSP_Length(n))
			peaks.append((min: lo, max: hi))
		}
		return peaks
	}

	override func draw(_ dirtyRect: NSRect) {
		NSColor.black.setFill()
		bounds.fill()
		guard peaks.count > 1 else { return }

		let w = bounds.width
		let h = bounds.height
		let mid = h / 2
		let step = w / CGFloat(peaks.count)

		let path = NSBezierPath()
		path.move(to: NSPoint(x: 0, y: mid + CGFloat(peaks[0].max) * mid))
		for (i, p) in peaks.enumerated() {
			path.line(to: NSPoint(x: CGFloat(i) * step, y: mid + CGFloat(p.max) * mid))
		}
		for (i, p) in peaks.enumerated().reversed() {
			path.line(to: NSPoint(x: CGFloat(i) * step, y: mid + CGFloat(p.min) * mid))
		}
		path.close()

		NSColor.systemGreen.setFill()
		path.fill()
	}
}
