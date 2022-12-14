//
//  GameViewController.swift
//  MetalGoL macOS
//
//  Created by Albertino Padin on 8/6/22.
//

import Cocoa
import Metal
import MetalKit
import GameController


enum VirtualKey: Int {
    case ANSI_A     = 0x00
    case ANSI_S     = 0x01
    case ANSI_D     = 0x02
    case ANSI_W     = 0x0D
    case leftArrow  = 0x7B
    case rightArrow = 0x7C
    case downArrow  = 0x7D
    case upArrow    = 0x7E
}

protocol GameWindowDelegate {
    func setGeneration(_ generation: UInt64)
}

// Our macOS specific view controller
class GameViewController: NSViewController {
    var mtkView: MTKView!
    var renderer: Renderer!
    var cameraController: FlyCameraController!
    var previousMousePoint = CGPoint.zero
    var currentMousePoint = CGPoint.zero
    var keysPressed = [Bool](repeating: false, count: Int(UInt16.max))
    var gameController: GCController?
    
    let nearClip: Float = 0.01
    let farClip: Float = 1000
    
    var eyeZPosition: Float = 400
    var generation: UInt64 = 0
    var gameRunning: Bool = false
    var previousTime: TimeInterval = 0
    var currentTime: TimeInterval = 0
    var updateInterval: TimeInterval = 0
    
    var delegate: GameWindowDelegate?

    private var observers = [Any]()
    
    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? MTKView else {
            print("View attached to GameViewController is not an MTKView")
            return
        }

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        
        renderer = Renderer(device: defaultDevice, view: mtkView, nearClip: nearClip, farClip: farClip)
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        
        cameraController = FlyCameraController(pointOfView: renderer.pointOfView)
        cameraController.eye = SIMD3<Float>(0, 0, eyeZPosition)
        
        mtkView.preferredFramesPerSecond = 120
        let frameDuration = 1.0 / Double(mtkView.preferredFramesPerSecond)
        print("Frame duration: \(frameDuration)")
        
        let displayId = CGMainDisplayID()
        let displayLinkPointer = UnsafeMutablePointer<CVDisplayLink?>.allocate(capacity: 1)
        let createDisplayLinkStatus = CVDisplayLinkCreateWithCGDisplay(displayId, displayLinkPointer)
        if createDisplayLinkStatus == kCVReturnSuccess {
            CVDisplayLinkSetOutputHandler(displayLinkPointer.pointee!) { [self]
                (dLink, inNow, inOutputTime, flagsIn, flagsOut) -> CVReturn in
                cameraController.eye = SIMD3<Float>(0, 0, eyeZPosition)
                updateCamera(Float(frameDuration))
                
                if gameRunning && currentTime >= (previousTime + updateInterval) {
                    previousTime = currentTime
                    let t_update = timeit {
                        generation = renderer.grid.update()
                        delegate?.setGeneration(generation)
                    }
                    print("Run time for Grid update: \(Double(t_update)/1_000_000) ms")
                }
                currentTime += frameDuration
                
                return kCVReturnSuccess
            }
            
            CVDisplayLinkStart(displayLinkPointer.pointee!)
        }
        
        registerControllerObservers()
    }
    
    func setGridColor(_ color: SIMD3<Float>) {
        renderer.grid.setGridCellsColor(color)
    }
    
    func toggleGameRunning() {
        gameRunning.toggle()
    }
    
    func reset() {
        renderer.grid.reset()
        generation = 0
        delegate?.setGeneration(generation)
        if gameRunning {
            gameRunning.toggle()
        }
    }
    
    func randomize() {
        renderer.grid.randomState(liveProbability: Grid.DefaultLiveProbability)
    }
    
    func setSpeed(_ speed: Int) {
        updateInterval = 1 / Double(speed)
    }
    
    func setZoom(_ zoom: Int) {
        eyeZPosition = Float(zoom)
    }
    
    func updateCamera(_ timestep: Float) {
        if let gamepad = gameController?.extendedGamepad {
            let lookX = gamepad.rightThumbstick.xAxis.value
            let lookZ = gamepad.rightThumbstick.yAxis.value
            let lookDelta = SIMD2<Float>(lookX, lookZ)
            let moveZ = gamepad.leftThumbstick.yAxis.value
            let moveDelta = SIMD2<Float>(0, moveZ)
            
            cameraController.update(timestep: timestep, lookDelta: lookDelta, moveDelta: moveDelta)
        } else {
            let cursorDeltaX = Float(currentMousePoint.x - previousMousePoint.x)
            let cursorDeltaY = Float(currentMousePoint.y - previousMousePoint.y)
            previousMousePoint = currentMousePoint
            let mouseDelta = SIMD2<Float>(cursorDeltaX, cursorDeltaY)
            
            let forwardPressed = keysPressed[VirtualKey.ANSI_W.rawValue]
            let backwardPressed = keysPressed[VirtualKey.ANSI_S.rawValue]
            let leftPressed = keysPressed[VirtualKey.ANSI_A.rawValue]
            let rightPressed = keysPressed[VirtualKey.ANSI_D.rawValue]
            
            let deltaX: Float = (leftPressed ? -1.0 : 0.0) + (rightPressed ? 1.0 : 0.0)
            let deltaZ: Float = (backwardPressed ? -1.0 : 0.0) + (forwardPressed ? 1.0 : 0.0)
            let keyDelta = SIMD2<Float>(deltaX, deltaZ)
            
            cameraController.update(timestep: timestep, lookDelta: mouseDelta, moveDelta: keyDelta)
        }
    }
    
    private func registerControllerObservers() {
        let connectionObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.GCControllerDidConnect,
                                                                        object: nil,
                                                                        queue: nil)
        { [weak self] notification in
            if let controller = notification.object as? GCController {
                self?.controllerDidConnect(controller)
            }
        }
        
        let disconnectionObserver =
        NotificationCenter.default.addObserver(forName: NSNotification.Name.GCControllerDidDisconnect,
                                               object: nil,
                                               queue: nil)
        { [weak self] notification in
            if let controller = notification.object as? GCController {
                self?.controllerDidDisconnect(controller)
            }
        }
        
        observers = [connectionObserver, disconnectionObserver]
    }
    
    func controllerDidConnect(_ controller: GCController) {
        gameController = controller
    }
    
    func controllerDidDisconnect(_ controller: GCController) {
        gameController = nil
    }
    
    override func viewDidAppear() {
        view.window?.makeFirstResponder(self)
    }
    
    override var acceptsFirstResponder: Bool {
        get {
            return true
        }
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
}
