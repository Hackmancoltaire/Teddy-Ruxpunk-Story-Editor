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

        guard let window = window else { return }
        window.setContentSize(NSSize(width: 960, height: 600))
        window.minSize = NSSize(width: 640, height: 500)
    }

}
