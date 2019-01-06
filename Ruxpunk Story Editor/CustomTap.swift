//
//  CustomTap.swift
//  Ruxpunk Story Editor
//
//  Created by Ramon Yvarra on 1/3/19.
//  Copyright © 2019 Ramon Yvarra. All rights reserved.
//

import Cocoa
import AudioKit
import SceneKit

open class CustomTap {
	let bufferSize: UInt32 = 1_024
	
	@objc public init(_ input: AKNode?, face: SCNView) {
		
		// This is how much silence we listen for to indicate the frame is about to change
		let pulseReset = 130
		var framePulse: Int = 0
		var pulseDistances: [Int] = Array(repeating: 0, count: 10)
		var pulse: Int = 0
		var currentFrame: Int = 0
		
		// SceneKit object references
		let leftEye: SCNNode = face.scene!.rootNode.childNode(withName: "left", recursively: true)!
		let rightEye: SCNNode = face.scene!.rootNode.childNode(withName: "right", recursively: true)!
		let topMouth: SCNNode = face.scene!.rootNode.childNode(withName: "topMouth", recursively: true)!
		topMouth.pivot = SCNMatrix4MakeTranslation(0, 0, -0.5)

		let bottomMouth: SCNNode = face.scene!.rootNode.childNode(withName: "bottomMouth", recursively: true)!
		bottomMouth.pivot = SCNMatrix4MakeTranslation(0, 0, -0.5)
		
		let grubbyLeftEye: SCNNode = face.scene!.rootNode.childNode(withName: "grubbyLeft", recursively: true)!
		let grubbyRightEye: SCNNode = face.scene!.rootNode.childNode(withName: "grubbyRight", recursively: true)!
		let grubbyTopMouth: SCNNode = face.scene!.rootNode.childNode(withName: "grubbyTopMouth", recursively: true)!
		grubbyTopMouth.pivot = SCNMatrix4MakeTranslation(0, 0, -0.5)
		
		let grubbyBottomMouth: SCNNode = face.scene!.rootNode.childNode(withName: "grubbyBottomMouth", recursively: true)!
		grubbyTopMouth.pivot = SCNMatrix4MakeTranslation(0, 0, -0.5)

		var eyePosition: Int = 0
		var topMouthPosition: Int = 0
		var bottomMouthPosition: Int = 0
		
		var grubbyEyePosition: Int = 0
		var grubbyTopMouthPosition: Int = 0
		var grubbyBottomMouthPosition: Int = 0
		
		input?.avAudioUnitOrNode.installTap(onBus: 0, bufferSize: bufferSize, format: AudioKit.format) { buffer, _ in
			buffer.frameLength = self.bufferSize
			
			// We process the buffer to look for pulse frames
			for currentElement in 0 ..< Int(self.bufferSize) {
				// Pull the data from the buffer
				let current: Float = Float(buffer.floatChannelData?.pointee[currentElement] ?? 1.0)
			
				if (current < 0) {
					// Low, either between pulses or between frames
					if (framePulse == 0) {
						pulse = pulse + 1
					}
					
					// Increase frame checker
					framePulse = framePulse + 1

					// Check to see if this is a new frame and reset counters
					if (framePulse == pulseReset) {
						// We rescale and clamp the incoming pulse data to our animation rotations
						eyePosition = Int(Rescale( from: (42,62), to: (0, 90)).rescale(Double(pulseDistances[2]))).clamped(to: 0...90)
						grubbyEyePosition = Int(Rescale( from: (42,62), to: (0, 90)).rescale(Double(pulseDistances[6]))).clamped(to: 0...90)
						
						topMouthPosition = Int(Rescale( from: (50,73), to: (0, 45)).rescale(Double(pulseDistances[3]))).clamped(to: 0...45)
						bottomMouthPosition = Int(Rescale( from: (45,65), to: (0, 45)).rescale(Double(pulseDistances[4]))).clamped(to: 0...45)
						
						grubbyTopMouthPosition = Int(Rescale( from: (50,73), to: (0, 45)).rescale(Double(pulseDistances[7]))).clamped(to: 0...45)
						grubbyBottomMouthPosition = Int(Rescale( from: (45,65), to: (0, 45)).rescale(Double(pulseDistances[8]))).clamped(to: 0...45)

						// print(pulseDistances)
						
						// Reset all these temporary values for the next frame
						framePulse = 0
						pulse = 0
						currentFrame = currentFrame + 1
						pulseDistances = Array(repeating: 0, count: 10)
					} else {
						// This is not a new frame, we are just between pulses
					}
				} else {
					// We are in a high state, reset he framepulse counter
					framePulse = 0
					
					// And start tracking the
					if (pulse < 10) {
						pulseDistances[pulse] = pulseDistances[pulse] + 1
					} else {
						// Ignore any pulses over 9. Sometimes there may be more interpretted because of tape damage
					}
				}
			}
			
			// Do animations in the SceneKit view
			SCNTransaction.begin()
			let eyeAction = SCNAction.rotateTo(x: CGFloat(self.degToRadians(Double(eyePosition))), y: 0, z: 0, duration: 0.1)
			let topMouthAction = SCNAction.rotateTo(x: CGFloat(self.degToRadians(Double(topMouthPosition+90))), y: 0, z: 0, duration: 0.1)
			let bottomMouthAction = SCNAction.rotateTo(x: CGFloat(self.degToRadians(Double((bottomMouthPosition+90) * -1))), y: 0, z: 0, duration: 0.1)
			
			let grubbyEyeAction = SCNAction.rotateTo(x: CGFloat(self.degToRadians(Double(grubbyEyePosition))), y: 0, z: 0, duration: 0.1)
			let grubbyTopMouthAction = SCNAction.rotateTo(x: CGFloat(self.degToRadians(Double(grubbyTopMouthPosition+90))), y: 0, z: 0, duration: 0.1)
			let grubbyBottomMouthAction = SCNAction.rotateTo(x: CGFloat(self.degToRadians(Double((grubbyBottomMouthPosition+90) * -1))), y: 0, z: 0, duration: 0.1)
			
			leftEye.runAction(eyeAction)
			rightEye.runAction(eyeAction)
			topMouth.runAction(topMouthAction)
			bottomMouth.runAction(bottomMouthAction)
			
			grubbyLeftEye.runAction(grubbyEyeAction)
			grubbyRightEye.runAction(grubbyEyeAction)
			grubbyTopMouth.runAction(grubbyTopMouthAction)
			grubbyBottomMouth.runAction(grubbyBottomMouthAction)
			
			SCNTransaction.commit()
		}
	}
	
	func degToRadians(_ degrees:Double) -> Double
	{
		return degrees * (.pi / 180)
	}
	
	func radiansToDeg(_ radians:Double) -> Double {
		return (radians * 180) / .pi
	}
}

extension Comparable {
	func clamped(to limits: ClosedRange<Self>) -> Self {
		return min(max(self, limits.lowerBound), limits.upperBound)
	}
}

extension Strideable where Stride: SignedInteger {
	func clamped(to limits: CountableClosedRange<Self>) -> Self {
		return min(max(self, limits.lowerBound), limits.upperBound)
	}
}

struct Rescale<Type : BinaryFloatingPoint> {
	typealias RescaleDomain = (lowerBound: Type, upperBound: Type)
	
	var fromDomain: RescaleDomain
	var toDomain: RescaleDomain
	
	init(from: RescaleDomain, to: RescaleDomain) {
		self.fromDomain = from
		self.toDomain = to
	}
	
	func interpolate(_ x: Type ) -> Type {
		return self.toDomain.lowerBound * (1 - x) + self.toDomain.upperBound * x;
	}
	
	func uninterpolate(_ x: Type) -> Type {
		let b = (self.fromDomain.upperBound - self.fromDomain.lowerBound) != 0 ? self.fromDomain.upperBound - self.fromDomain.lowerBound : 1 / self.fromDomain.upperBound;
		return (x - self.fromDomain.lowerBound) / b
	}
	
	func rescale(_ x: Type )  -> Type {
		return interpolate( uninterpolate(x) )
	}
}
