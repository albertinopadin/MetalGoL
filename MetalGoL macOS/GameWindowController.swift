//
//  GameWindowController.swift
//  MetalGoL macOS
//
//  Created by Albertino Padin on 9/1/22.
//

import Cocoa

enum GameState: String {
    case play = "Play"
    case pause = "Pause"
}

class GameWindowController: NSWindowController, GameWindowDelegate {
    @IBOutlet weak var playPauseButton: NSButton!
    @IBOutlet weak var generationLabel: NSTextField!
    @IBOutlet weak var speedLabel: NSTextField!
    
    var gameVC: GameViewController!
    
    override func windowDidLoad() {
        super.windowDidLoad()
    
        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        gameVC = self.contentViewController as? GameViewController
        gameVC.delegate = self
    }
    
    @IBAction func setColor(_ sender: Any) {
    }
    
    func setPlayPauseButtonText() {
        if gameVC.gameRunning {
            playPauseButton.title = GameState.pause.rawValue
        } else {
            playPauseButton.title = GameState.play.rawValue
        }
    }
    
    @IBAction func playPauseToggled(_ sender: NSButton) {
        gameVC.toggleGameRunning()
        setPlayPauseButtonText()
    }
    
    func setGeneration(_ generation: UInt64) {
        generationLabel.integerValue = Int(generation)
    }
    
    @IBAction func reset(_ sender: NSButton) {
        gameVC.reset()
        setPlayPauseButtonText()
    }
    
    @IBAction func randomize(_ sender: NSButton) {
        gameVC.randomize()
    }
    
    @IBAction func setSpeed(_ sender: NSSlider) {
        gameVC.setSpeed(sender.integerValue)
        speedLabel.intValue = sender.intValue
    }
    
    @IBAction func setZoom(_ sender: NSSlider) {
    }
}
