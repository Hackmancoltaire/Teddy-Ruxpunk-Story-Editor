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
	@IBOutlet weak var scrollView: NSScrollView?
	@IBOutlet weak var scene: SCNView?

	let engine = AudioEngine()
	var storyPlayer: AudioPlayer = AudioPlayer()

	var document: Document? {
		return view.window?.windowController?.document as? Document
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		// Do any additional setup after loading the view.
	}

	deinit {
		engine.stop()
	}

	@IBAction func playPause(_: AnyObject!) {
		// This doesn't work quite right. It restarts the track for some reason
		if (self.storyPlayer.isPlaying) {
			self.storyPlayer.pause()

		} else {
			self.storyPlayer.play()
		}
	}

	@IBAction func rotateEyes(slider: NSSlider!) {
		NSLog("Rotated Eyes: %i", slider.intValue)

		let leftEye: SCNNode = scene!.scene!.rootNode.childNode(withName: "left", recursively: true)!
		let rightEye: SCNNode = scene!.scene!.rootNode.childNode(withName: "right", recursively: true)!

		NSLog("X: %f", leftEye.rotation.w)

		let rotation = SCNVector4(x: 1.0, y: 0.0, z: 0.0, w: CGFloat(self.degToRadians(slider.doubleValue)))

		leftEye.rotation = rotation
		rightEye.rotation = rotation
	}

	func updateView() {
		let document = self.view.window?.windowController?.document as! Document

		// --- Audio engine setup (fast, stays on main thread) ---

		// Create a player for the file
		self.storyPlayer = AudioPlayer(file: document.file)!

		// Build the node graph first, set parameters after connecting to engine
		let leftChannel = Fader(storyPlayer)
		let rightChannel = Fader(storyPlayer)
		let rightExpander = StereoFieldLimiter(rightChannel)
		let rightChannelMixer = Mixer(rightExpander)
		let stereoExpander = StereoFieldLimiter(leftChannel)
		let mixer = Mixer(stereoExpander, rightChannelMixer)

		// Connect graph to engine (nodes get attached to the underlying AVAudioEngine here)
		engine.output = mixer

		// Set parameters after nodes are connected to avoid kAudioUnitErr_InvalidParameter
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

		// Install the tap after the engine is running (AVAudioNode must be attached to a running AVAudioEngine)
		_ = CustomTap(rightExpander, face: scene!)

		// --- Waveform display (reads file in small chunks, computes peaks per pixel) ---
		let waveformView = WaveformView()
		waveformView.setFrameSize(NSMakeSize(2000, 150))
		waveformView.autoresizingMask = [.height]
		scrollView!.documentView = waveformView
		waveformView.load(document.fileURL!, peakCount: 2000)
	}

	override var representedObject: Any? {
		didSet {
		// Update the view, if already loaded.
		}
	}

	func degToRadians(_ degrees:Double) -> Double
	{
		return degrees * (.pi / 180);
	}
}
