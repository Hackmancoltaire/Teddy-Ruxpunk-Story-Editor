//
//  ViewController.swift
//  Ruxpunk Story Editor
//
//  Created by Ramon Yvarra on 1/1/19.
//  Copyright © 2019 Ramon Yvarra. All rights reserved.
//

import Cocoa
import AVFoundation
import AudioKit
import AudioKitEX
import SceneKit

class ViewController: NSViewController {

	// MARK: - Views (all programmatic)
	var sceneView: SCNView!
	var timelineScrollView: NSScrollView!
	var containerView: TimelineContainerView!
	var waveformView: WaveformView!
	var playheadView: PlayheadView!
	var playPauseButton: NSButton!
	var zoomInButton: NSButton!
	var zoomOutButton: NSButton!

	// MARK: - Audio
	let engine = AudioEngine()
	var storyPlayer: AudioPlayer = AudioPlayer()
	var customTap: CustomTap?

	// MARK: - Timeline state
	var parameterViews: [ParameterWaveformView] = []
	var playheadTimer: Timer?
	var pixelsPerSecond: CGFloat = 100.0
	var cachedAnalysisResults: [(samplePosition: Int, frame: DecodedFrame)] = []
	var cachedTotalSamples: Int = 0
	var scrollObserver: NSObjectProtocol?

	// MARK: - Cached scene node references (for sync'd animation from offline data)
	private var nodeLeftEye: SCNNode?
	private var nodeRightEye: SCNNode?
	private var nodeTopMouth: SCNNode?
	private var nodeBottomMouth: SCNNode?
	private var nodeGrubbyLeftEye: SCNNode?
	private var nodeGrubbyRightEye: SCNNode?
	private var nodeGrubbyTopMouth: SCNNode?
	private var nodeGrubbyBottomMouth: SCNNode?

	// MARK: - Layout constants
	let sceneViewHeight: CGFloat = 200
	let transportBarHeight: CGFloat = 36
	let waveformHeight: CGFloat = 150
	let paramHeight: CGFloat = 30

	let paramConfigs: [(label: String, color: NSColor, maxValue: CGFloat, keyPath: KeyPath<DecodedFrame, Int>)] = [
		("Teddy Eyes",       .systemOrange, 90, \.eyePosition),
		("Teddy Top Mouth",  .systemYellow, 45, \.topMouthPosition),
		("Teddy Btm Mouth",  .systemRed,    45, \.bottomMouthPosition),
		("Grubby Eyes",      .systemCyan,   90, \.grubbyEyePosition),
		("Grubby Top Mouth", .systemBlue,   45, \.grubbyTopMouthPosition),
		("Grubby Btm Mouth", .systemPurple, 45, \.grubbyBottomMouthPosition),
	]

	var document: Document? {
		return view.window?.windowController?.document as? Document
	}

	// MARK: - Computed
	var containerHeight: CGFloat {
		waveformHeight + paramHeight * CGFloat(paramConfigs.count)
	}

	var timelineWidth: CGFloat {
		CGFloat(storyPlayer.duration) * pixelsPerSecond
	}

	// MARK: - Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()

		// Remove any storyboard subviews
		view.subviews.forEach { $0.removeFromSuperview() }
		view.wantsLayer = true
		view.layer?.backgroundColor = NSColor.black.cgColor

		setupSceneView()
		setupTransportBar()
		setupTimelineScrollView()
	}

	deinit {
		if let observer = scrollObserver {
			NotificationCenter.default.removeObserver(observer)
		}
		playheadTimer?.invalidate()
		playheadTimer = nil
		engine.stop()
	}

	override var acceptsFirstResponder: Bool { true }

	override func viewDidLayout() {
		super.viewDidLayout()
		updateVisibleContent()
	}

	// MARK: - View Setup

	private func setupSceneView() {
		sceneView = SCNView()
		sceneView.translatesAutoresizingMaskIntoConstraints = false
		sceneView.scene = SCNScene(named: "Face.scn")
		sceneView.allowsCameraControl = false
		sceneView.autoenablesDefaultLighting = true
		view.addSubview(sceneView)
		cacheSceneNodes()

		NSLayoutConstraint.activate([
			sceneView.topAnchor.constraint(equalTo: view.topAnchor),
			sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			sceneView.heightAnchor.constraint(equalToConstant: sceneViewHeight),
		])
	}

	private func setupTransportBar() {
		let bar = NSView()
		bar.translatesAutoresizingMaskIntoConstraints = false
		bar.wantsLayer = true
		bar.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1).cgColor
		view.addSubview(bar)

		playPauseButton = NSButton(title: "Play", target: self, action: #selector(playPause(_:)))
		playPauseButton.translatesAutoresizingMaskIntoConstraints = false
		playPauseButton.bezelStyle = .rounded
		bar.addSubview(playPauseButton)

		zoomInButton = NSButton(title: "Zoom +", target: self, action: #selector(zoomIn(_:)))
		zoomInButton.translatesAutoresizingMaskIntoConstraints = false
		zoomInButton.bezelStyle = .rounded
		bar.addSubview(zoomInButton)

		zoomOutButton = NSButton(title: "Zoom -", target: self, action: #selector(zoomOut(_:)))
		zoomOutButton.translatesAutoresizingMaskIntoConstraints = false
		zoomOutButton.bezelStyle = .rounded
		bar.addSubview(zoomOutButton)

		NSLayoutConstraint.activate([
			bar.topAnchor.constraint(equalTo: sceneView.bottomAnchor),
			bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			bar.heightAnchor.constraint(equalToConstant: transportBarHeight),

			playPauseButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
			playPauseButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),

			zoomOutButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
			zoomOutButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),

			zoomInButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
			zoomInButton.trailingAnchor.constraint(equalTo: zoomOutButton.leadingAnchor, constant: -4),
		])
	}

	private func setupTimelineScrollView() {
		timelineScrollView = NSScrollView()
		timelineScrollView.translatesAutoresizingMaskIntoConstraints = false
		timelineScrollView.hasHorizontalScroller = true
		timelineScrollView.hasVerticalScroller = false
		timelineScrollView.allowsMagnification = false
		timelineScrollView.usesPredominantAxisScrolling = true
		timelineScrollView.drawsBackground = true
		timelineScrollView.backgroundColor = .black
		timelineScrollView.contentView.drawsBackground = true
		timelineScrollView.contentView.backgroundColor = .black
		view.addSubview(timelineScrollView)

		// Scroll change observer — drives viewport rendering
		timelineScrollView.contentView.postsBoundsChangedNotifications = true
		scrollObserver = NotificationCenter.default.addObserver(
			forName: NSView.boundsDidChangeNotification,
			object: timelineScrollView.contentView,
			queue: .main
		) { [weak self] _ in
			self?.updateVisibleContent()
		}

		// Pinch-to-zoom gesture
		let magnification = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
		timelineScrollView.addGestureRecognizer(magnification)

		NSLayoutConstraint.activate([
			timelineScrollView.topAnchor.constraint(equalTo: sceneView.bottomAnchor, constant: transportBarHeight),
			timelineScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			timelineScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			timelineScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
		])
	}

	// MARK: - updateView (called after file load)

	func updateView() {
		NSLog("[updateView] called")
		guard let document = self.document else { return }

		// --- Audio engine setup ---
		self.storyPlayer = AudioPlayer(file: document.file)!

		let leftChannel = Fader(storyPlayer)
		let rightChannel = Fader(storyPlayer)
		let rightExpander = StereoFieldLimiter(rightChannel)
		let rightChannelMixer = Mixer(rightExpander)
		let stereoExpander = StereoFieldLimiter(leftChannel)
		let mixer = Mixer(stereoExpander, rightChannelMixer)

		engine.output = mixer

		leftChannel.rightGain = 0.0
		rightChannel.leftGain = 0.0
		rightExpander.amount = 1.0
		rightChannelMixer.volume = 0
		stereoExpander.amount = 1.0

		do {
			try engine.start()
		} catch {
			print("Could not start audiokit")
		}

		// Install the tap after the engine is running
		let tap = CustomTap(rightExpander, face: sceneView)
		self.customTap = tap

		// --- Build timeline ---
		buildTimeline()

		// --- Offline analysis on background queue ---
		guard let fileURL = document.fileURL else { return }

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			guard let self = self else { return }
			guard let audioFile = try? AVAudioFile(forReading: fileURL) else {
				NSLog("[Timeline] Could not open file for offline analysis")
				return
			}
			let results = CustomTap.analyzeFile(audioFile)
			let totalSamples = Int(audioFile.length)
			guard totalSamples > 0, !results.isEmpty else { return }

			DispatchQueue.main.async {
				self.cachedAnalysisResults = results
				self.cachedTotalSamples = totalSamples
				self.applyAnalysisToParameterViews()
			}
		}

		// --- Playhead timer at ~30fps ---
		startPlayheadTimer()
	}

	// MARK: - Timeline Building

	private func buildTimeline() {
		let tw = max(timelineWidth, timelineScrollView.contentSize.width)
		let viewportWidth = timelineScrollView.contentSize.width

		// Container at full timeline width (sets scrollbar range, draws nothing)
		let container = TimelineContainerView(frame: NSRect(x: 0, y: 0, width: tw, height: containerHeight))
		container.onSeek = { [weak self] normalized in
			guard let self = self else { return }
			let time = TimeInterval(normalized) * self.storyPlayer.duration
			self.seekTo(time: time)
		}
		self.containerView = container
		timelineScrollView.documentView = container

		// Waveform — viewport-width, positioned at scroll offset
		let wv = WaveformView()
		wv.frame = NSRect(x: 0, y: 0, width: viewportWidth, height: waveformHeight)
		container.addSubview(wv)
		self.waveformView = wv

		if let fileURL = document?.fileURL {
			wv.load(fileURL)
		}

		// Parameter lanes — viewport-width each
		for pv in parameterViews { pv.removeFromSuperview() }
		parameterViews.removeAll()

		for (i, config) in paramConfigs.enumerated() {
			let yPos = waveformHeight + CGFloat(i) * paramHeight
			let pv = ParameterWaveformView(frame: NSRect(x: 0, y: yPos, width: viewportWidth, height: paramHeight))
			pv.configure(label: config.label, color: config.color, maxValue: config.maxValue)
			container.addSubview(pv)
			parameterViews.append(pv)
		}

		// Playhead (full container height, scrolls naturally with content)
		let playhead = PlayheadView(frame: NSRect(x: 0, y: 0, width: 2, height: containerHeight))
		container.addSubview(playhead)
		self.playheadView = playhead

		// Initial render of visible content
		updateVisibleContent()
	}

	// MARK: - Viewport Rendering (called on every scroll, zoom, and resize)

	func updateVisibleContent() {
		guard let container = containerView, let sv = timelineScrollView else { return }

		let visibleRect = sv.contentView.bounds
		let tw = container.bounds.width
		let viewportWidth = visibleRect.width
		let offsetX = visibleRect.minX
		let offsetPixel = Int(offsetX)

		// Reposition and re-render waveform
		if let wv = waveformView {
			wv.frame = NSRect(x: offsetX, y: 0, width: viewportWidth, height: waveformHeight)
			wv.updateDisplay(offset: offsetPixel, pixelsPerSecond: pixelsPerSecond)
		}

		// Reposition and re-render parameter lanes
		for (i, pv) in parameterViews.enumerated() {
			let yPos = waveformHeight + CGFloat(i) * paramHeight
			pv.frame = NSRect(x: offsetX, y: yPos, width: viewportWidth, height: paramHeight)
			pv.updateDisplay(offset: offsetPixel, timelineWidth: Int(tw))
		}
	}

	// MARK: - Zoom

	private func rebuildTimelineForZoom(centeredOnMouseX mouseXInWindow: CGFloat? = nil) {
		let sv = timelineScrollView!
		let oldVisibleRect = sv.contentView.bounds
		let oldContentWidth = containerView?.bounds.width ?? 1

		// Anchor point for zoom centering
		let anchorXInContent: CGFloat
		if let mx = mouseXInWindow {
			let localPoint = sv.contentView.convert(NSPoint(x: mx, y: 0), from: nil)
			anchorXInContent = localPoint.x
		} else {
			anchorXInContent = oldVisibleRect.midX
		}
		let anchorFraction = anchorXInContent / oldContentWidth

		let tw = max(timelineWidth, sv.contentSize.width)

		// Resize container (updates scrollbar range)
		containerView.frame.size.width = tw

		// Adjust scroll position to keep anchor point stable
		let newAnchorX = anchorFraction * tw
		let anchorScreenOffset = anchorXInContent - oldVisibleRect.origin.x
		let newScrollX = (newAnchorX - anchorScreenOffset).clamped(to: 0...(max(0, tw - sv.contentSize.width)))
		sv.contentView.setBoundsOrigin(NSPoint(x: newScrollX, y: 0))
		sv.reflectScrolledClipView(sv.contentView)

		// The scroll change notification will fire updateVisibleContent()
	}

	private func applyAnalysisToParameterViews() {
		guard cachedTotalSamples > 0 else { return }
		let keyPaths = paramConfigs.map { $0.keyPath }

		var pointArrays: [[(normalizedX: CGFloat, rawValue: CGFloat)]] = Array(repeating: [], count: keyPaths.count)
		for r in cachedAnalysisResults {
			let nx = CGFloat(r.samplePosition) / CGFloat(cachedTotalSamples)
			for (j, kp) in keyPaths.enumerated() {
				pointArrays[j].append((normalizedX: nx, rawValue: CGFloat(r.frame[keyPath: kp])))
			}
		}

		for (j, pv) in parameterViews.enumerated() {
			pv.loadTimeline(points: pointArrays[j])
		}

		// Trigger re-render with the new data
		updateVisibleContent()
	}

	// MARK: - Playhead Timer

	private func startPlayheadTimer() {
		playheadTimer?.invalidate()
		let player = self.storyPlayer
		playheadTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
			guard let self = self,
				  let playhead = self.playheadView else { return }

			let duration = player.duration
			guard duration > 0 else { return }

			let currentTime = player.currentTime
			let tw = self.containerView?.bounds.width ?? 1
			let x = CGFloat(currentTime / duration) * tw

			playhead.frame.origin.x = x

			// Sync 3D scene to current playback position (works during play AND pause)
			if let frame = self.frameForTime(currentTime) {
				self.applyFrameToScene(frame)
			}

			// Update button title
			self.playPauseButton.title = player.isPlaying ? "Pause" : "Play"

			// Auto-scroll to keep playhead visible during playback
			if player.isPlaying {
				let visibleRect = self.timelineScrollView.contentView.bounds
				let rightThreshold = visibleRect.maxX - visibleRect.width * 0.2
				if x > rightThreshold || x < visibleRect.minX {
					let scrollX = max(0, x - visibleRect.width * 0.25)
					let clampedX = min(scrollX, tw - visibleRect.width)
					self.timelineScrollView.contentView.setBoundsOrigin(NSPoint(x: max(0, clampedX), y: 0))
					self.timelineScrollView.reflectScrolledClipView(self.timelineScrollView.contentView)
				}
			}
		}
	}

	// MARK: - Seek

	func seekTo(time: TimeInterval) {
		let duration = storyPlayer.duration
		guard duration > 0 else { return }
		let clamped = time.clamped(to: 0...duration)

		let wasPlaying = storyPlayer.isPlaying
		if wasPlaying { storyPlayer.stop() }
		storyPlayer.play(from: clamped)
		if !wasPlaying { storyPlayer.pause() }

		// Immediately update scene and playhead for responsive scrubbing
		if let frame = frameForTime(clamped) {
			applyFrameToScene(frame)
		}
		if let playhead = playheadView, let container = containerView {
			let tw = container.bounds.width
			playhead.frame.origin.x = CGFloat(clamped / duration) * tw
		}
	}

	// MARK: - Transport Actions

	@objc func playPause(_ sender: Any?) {
		if storyPlayer.isPlaying {
			storyPlayer.pause()
		} else {
			storyPlayer.play()
		}
	}

	@objc func zoomIn(_ sender: Any?) {
		applyZoom(factor: 1.5)
	}

	@objc func zoomOut(_ sender: Any?) {
		applyZoom(factor: 1.0 / 1.5)
	}

	private func applyZoom(factor: CGFloat, mouseXInWindow: CGFloat? = nil) {
		pixelsPerSecond = (pixelsPerSecond * factor).clamped(to: 10...2000)
		rebuildTimelineForZoom(centeredOnMouseX: mouseXInWindow)
	}

	// MARK: - Keyboard Zoom

	override func keyDown(with event: NSEvent) {
		let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		if flags.contains(.command) {
			switch event.charactersIgnoringModifiers {
			case "=", "+":
				applyZoom(factor: 1.5)
				return
			case "-":
				applyZoom(factor: 1.0 / 1.5)
				return
			default:
				break
			}
		}
		// Space bar to play/pause
		if event.keyCode == 49 {
			playPause(nil)
			return
		}
		super.keyDown(with: event)
	}

	// MARK: - Pinch Zoom

	@objc func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
		let factor = 1.0 + gesture.magnification
		gesture.magnification = 0
		let mouseX = gesture.location(in: nil).x
		applyZoom(factor: factor, mouseXInWindow: mouseX)
	}

	// MARK: - Scene Animation (driven from cached offline analysis)

	private func cacheSceneNodes() {
		guard let root = sceneView.scene?.rootNode else { return }
		nodeLeftEye = root.childNode(withName: "left", recursively: true)
		nodeRightEye = root.childNode(withName: "right", recursively: true)
		nodeTopMouth = root.childNode(withName: "topMouth", recursively: true)
		nodeBottomMouth = root.childNode(withName: "bottomMouth", recursively: true)
		nodeGrubbyLeftEye = root.childNode(withName: "grubbyLeft", recursively: true)
		nodeGrubbyRightEye = root.childNode(withName: "grubbyRight", recursively: true)
		nodeGrubbyTopMouth = root.childNode(withName: "grubbyTopMouth", recursively: true)
		nodeGrubbyBottomMouth = root.childNode(withName: "grubbyBottomMouth", recursively: true)

		// Set pivots for mouth rotation (same as CustomTap does)
		nodeTopMouth?.pivot = SCNMatrix4MakeTranslation(0, 0, -0.5)
		nodeBottomMouth?.pivot = SCNMatrix4MakeTranslation(0, 0, -0.5)
		nodeGrubbyTopMouth?.pivot = SCNMatrix4MakeTranslation(0, 0, -0.5)
		nodeGrubbyBottomMouth?.pivot = SCNMatrix4MakeTranslation(0, 0, -0.5)
	}

	/// Binary search for the nearest animation frame at the given playback time
	private func frameForTime(_ time: TimeInterval) -> DecodedFrame? {
		guard !cachedAnalysisResults.isEmpty, cachedTotalSamples > 0 else { return nil }
		let duration = storyPlayer.duration
		guard duration > 0 else { return nil }

		let targetSample = Int((time / duration) * Double(cachedTotalSamples))

		// Binary search: find the last frame at or before targetSample
		var lo = 0, hi = cachedAnalysisResults.count - 1
		while lo < hi {
			let mid = (lo + hi + 1) / 2
			if cachedAnalysisResults[mid].samplePosition <= targetSample {
				lo = mid
			} else {
				hi = mid - 1
			}
		}
		return cachedAnalysisResults[lo].frame
	}

	/// Apply a decoded animation frame to the 3D scene (immediate, no animation lag)
	private func applyFrameToScene(_ frame: DecodedFrame) {
		let eyeRad = CGFloat(degToRadians(Double(frame.eyePosition)))
		let topMouthRad = CGFloat(degToRadians(Double(frame.topMouthPosition + 90)))
		let btmMouthRad = CGFloat(degToRadians(Double((frame.bottomMouthPosition + 90) * -1)))
		let grubbyEyeRad = CGFloat(degToRadians(Double(frame.grubbyEyePosition)))
		let grubbyTopRad = CGFloat(degToRadians(Double(frame.grubbyTopMouthPosition + 90)))
		let grubbyBtmRad = CGFloat(degToRadians(Double((frame.grubbyBottomMouthPosition + 90) * -1)))

		SCNTransaction.begin()
		SCNTransaction.animationDuration = 0

		nodeLeftEye?.removeAllActions()
		nodeRightEye?.removeAllActions()
		nodeTopMouth?.removeAllActions()
		nodeBottomMouth?.removeAllActions()
		nodeGrubbyLeftEye?.removeAllActions()
		nodeGrubbyRightEye?.removeAllActions()
		nodeGrubbyTopMouth?.removeAllActions()
		nodeGrubbyBottomMouth?.removeAllActions()

		nodeLeftEye?.eulerAngles = SCNVector3(eyeRad, 0, 0)
		nodeRightEye?.eulerAngles = SCNVector3(eyeRad, 0, 0)
		nodeTopMouth?.eulerAngles = SCNVector3(topMouthRad, 0, 0)
		nodeBottomMouth?.eulerAngles = SCNVector3(btmMouthRad, 0, 0)
		nodeGrubbyLeftEye?.eulerAngles = SCNVector3(grubbyEyeRad, 0, 0)
		nodeGrubbyRightEye?.eulerAngles = SCNVector3(grubbyEyeRad, 0, 0)
		nodeGrubbyTopMouth?.eulerAngles = SCNVector3(grubbyTopRad, 0, 0)
		nodeGrubbyBottomMouth?.eulerAngles = SCNVector3(grubbyBtmRad, 0, 0)

		SCNTransaction.commit()
	}

	// MARK: - Utilities

	override var representedObject: Any? {
		didSet {
		}
	}

	func degToRadians(_ degrees: Double) -> Double {
		return degrees * (.pi / 180)
	}
}
