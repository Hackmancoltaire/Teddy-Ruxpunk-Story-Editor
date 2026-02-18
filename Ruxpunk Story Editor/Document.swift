//
//  Document.swift
//  Ruxpunk Story Editor
//
//  Created by Ramon Yvarra on 1/1/19.
//  Copyright © 2019 Ramon Yvarra. All rights reserved.
//

import Cocoa
import AVFoundation

class Document: NSDocument {

	var file: AVAudioFile!

	var viewController: ViewController? {
		return windowControllers[0].contentViewController as? ViewController
	}

	override init() {
		super.init()

		// Add your subclass-specific initialization here.
	}

	override class var autosavesInPlace: Bool {
		return false
	}

	override func makeWindowControllers() {
		// Returns the Storyboard that contains your Document window.
		let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
		let windowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("Document Window Controller")) as! NSWindowController

		self.addWindowController(windowController)

		if ((self.file) != nil) {
			// If we opened a file then update the view
			self.viewController!.updateView()
		}
	}

	override func data(ofType typeName: String) throws -> Data {
		// Insert code here to write your document to data of the specified type, throwing an error in case of failure.
		// Alternatively, you could remove this method and override fileWrapper(ofType:), write(to:ofType:), or write(to:ofType:for:originalContentsURL:) instead.
		throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
	}

	override func read(from data: Data, ofType typeName: String) throws {
		NSLog(fileURL!.path)

		do {
			self.file = try AVAudioFile(forReading: fileURL!)
		} catch {
			NSLog("WHAT?!")
		}

//		NSLog("ElementCount: %i", file.floatChannelData?[1].count ?? 0)
	}


}
