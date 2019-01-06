//
//  ViewController.swift
//  Ruxpunk Story Editor
//
//  Created by Ramon Yvarra on 1/1/19.
//  Copyright © 2019 Ramon Yvarra. All rights reserved.
//

import Cocoa
import AudioKit
import AudioKitUI
import SceneKit

class ViewController: NSViewController {
	@IBOutlet weak var scrollView: NSScrollView?
	@IBOutlet weak var scene: SCNView?
	
	var storyPlayer: AKPlayer = AKPlayer()
	
	var document: Document? {
		return view.window?.windowController?.document as? Document
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		// Do any additional setup after loading the view.
	}
	
	@IBAction func playPause(_: AnyObject!) {
		// This doesn't work quite right. It restarts the track for some reason
		if (self.storyPlayer.isPlaying) {
			self.storyPlayer.pause()
			
		} else {
			self.storyPlayer.resume()
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
		// Fill the text view with the document's contents.
		let document = self.view.window?.windowController?.document as! Document
		
		let fileTable = AKTable(file: document.file)
		
		var view = AKTableView(fileTable)
		
		view.setFrameSize(NSMakeSize(2000, 150))
		view.autoresizingMask = [.height]
		
		scrollView!.documentView = view

		// This is where all the audio file channel splitting happens
		
		// Create a player for the file
		self.storyPlayer = AKPlayer(audioFile: document.file)

		// Create a "booster" for the left channel that takes the player and lowers the gain on the data channel
		let leftChannel = AKBooster(storyPlayer)
		leftChannel.rightGain = 0.0
		
		// And create another booster that lowers the gain on the story channel
		let rightChannel = AKBooster(storyPlayer)
		rightChannel.leftGain = 0.0
		
		// The tap will need the audio to take up the entire float channel, so we make the data channel in the expander fully stereo
		let rightExpander = AKStereoFieldLimiter(rightChannel)
		rightExpander.amount = 1.0

		// Now we add a tap to the expander so we can listen to the data track
		var tap = CustomTap(rightExpander, face: scene!)
		
		// But we still need the data channel to have an output otherwise the bus is empty.
		// So create a mixer for the data channel and effectively mute it
		let rightChannelMixer = AKMixer(rightExpander)
		rightChannelMixer.volume = 0
		
		// For a better listening experience we convert the story track to stereo
		let stereoExpander = AKStereoFieldLimiter(leftChannel)
		stereoExpander.amount = 1.0
		
		// And finally add both channels to a mixer, that becomes our output
		let mixer = AKMixer(stereoExpander,rightChannelMixer)
		
		AudioKit.output = mixer
		
		do {
			try AudioKit.start()
		} catch {
			print("Could not start audiokit")
		}
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
