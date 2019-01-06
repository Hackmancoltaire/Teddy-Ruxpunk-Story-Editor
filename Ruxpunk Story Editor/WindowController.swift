//
//  WindowController.swift
//  Ruxpunk Story Editor
//
//  Created by Ramon Yvarra on 1/3/19.
//  Copyright © 2019 Ramon Yvarra. All rights reserved.
//

import Cocoa

class WindowController: NSWindowController {

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		shouldCascadeWindows = true
	}
	
    override func windowDidLoad() {
        super.windowDidLoad()
    
        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    }

}
