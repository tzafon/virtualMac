/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app delegate that sets up and starts the virtual machine.
*/

import Cocoa
import Foundation
import Virtualization

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!

    @IBOutlet weak var virtualMachineView: VZVirtualMachineView!

    private var virtualMachineResponder: MacOSVirtualMachineDelegate?

    private var virtualMachine: VZVirtualMachine!
    
    // MARK: - Shared instance for programmatic control
    static weak var sharedInstance: AppDelegate?

    // MARK: Create the Mac platform configuration.

#if arch(arm64)
    private func createMacPlaform() -> VZMacPlatformConfiguration {
        let macPlatform = VZMacPlatformConfiguration()

        let auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: auxiliaryStorageURL)
        macPlatform.auxiliaryStorage = auxiliaryStorage

        if !FileManager.default.fileExists(atPath: vmBundlePath) {
            fatalError("Missing Virtual Machine Bundle at \(vmBundlePath). Run InstallationTool first to create it.")
        }

        // Retrieve the hardware model and save this value to disk
        // during installation.
        guard let hardwareModelData = try? Data(contentsOf: hardwareModelURL) else {
            fatalError("Failed to retrieve hardware model data.")
        }

        guard let hardwareModel = VZMacHardwareModel(dataRepresentation: hardwareModelData) else {
            fatalError("Failed to create hardware model.")
        }

        if !hardwareModel.isSupported {
            fatalError("The hardware model isn't supported on the current host")
        }
        macPlatform.hardwareModel = hardwareModel

        // Retrieve the machine identifier and save this value to disk
        // during installation.
        guard let machineIdentifierData = try? Data(contentsOf: machineIdentifierURL) else {
            fatalError("Failed to retrieve machine identifier data.")
        }

        guard let machineIdentifier = VZMacMachineIdentifier(dataRepresentation: machineIdentifierData) else {
            fatalError("Failed to create machine identifier.")
        }
        macPlatform.machineIdentifier = machineIdentifier

        return macPlatform
    }

    // MARK: Create the virtual machine configuration and instantiate the virtual machine.

    private func createVirtualMachine() {
        let virtualMachineConfiguration = VZVirtualMachineConfiguration()

        virtualMachineConfiguration.platform = createMacPlaform()
        virtualMachineConfiguration.bootLoader = MacOSVirtualMachineConfigurationHelper.createBootLoader()
        virtualMachineConfiguration.cpuCount = MacOSVirtualMachineConfigurationHelper.computeCPUCount()
        virtualMachineConfiguration.memorySize = MacOSVirtualMachineConfigurationHelper.computeMemorySize()

        virtualMachineConfiguration.audioDevices = [MacOSVirtualMachineConfigurationHelper.createSoundDeviceConfiguration()]
        virtualMachineConfiguration.graphicsDevices = [MacOSVirtualMachineConfigurationHelper.createGraphicsDeviceConfiguration()]
        virtualMachineConfiguration.networkDevices = [MacOSVirtualMachineConfigurationHelper.createNetworkDeviceConfiguration()]
        virtualMachineConfiguration.storageDevices = [MacOSVirtualMachineConfigurationHelper.createBlockDeviceConfiguration()]

        virtualMachineConfiguration.pointingDevices = [MacOSVirtualMachineConfigurationHelper.createPointingDeviceConfiguration()]
        virtualMachineConfiguration.keyboards = [MacOSVirtualMachineConfigurationHelper.createKeyboardConfiguration()]

        try! virtualMachineConfiguration.validate()

        if #available(macOS 14.0, *) {
            try! virtualMachineConfiguration.validateSaveRestoreSupport()
        }

        virtualMachine = VZVirtualMachine(configuration: virtualMachineConfiguration)
    }

    // MARK: Start or restore the virtual machine.

    func startVirtualMachine() {
        virtualMachine.start(completionHandler: { [weak self] (result) in
            if case let .failure(error) = result {
                fatalError("Virtual machine failed to start with \(error)")
            } else {
                print("✅ Virtual Machine started successfully")
                print("🎛️ Starting programmatic input control server...")
                VMControlServer.shared.startListening()
                
                // Demo: Automatically open Finder after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    print("🤖 Demo: Opening Finder programmatically...")
                    self?.injectKeyPress(keyCode: 0x31, modifierFlags: [.command]) // Cmd+Space
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self?.injectText("Finder")
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self?.injectKeyPress(keyCode: 0x24) // Enter
                        }
                    }
                }
            }
        })
    }

    func resumeVirtualMachine() {
        virtualMachine.resume(completionHandler: { (result) in
            if case let .failure(error) = result {
                fatalError("Virtual machine failed to resume with \(error)")
            }
        })
    }

    @available(macOS 14.0, *)
    func restoreVirtualMachine() {
        virtualMachine.restoreMachineStateFrom(url: saveFileURL, completionHandler: { [self] (error) in
            // Remove the saved file. Whether success or failure, the state no longer matches the VM's disk.
            let fileManager = FileManager.default
            try! fileManager.removeItem(at: saveFileURL)

            if error == nil {
                self.resumeVirtualMachine()
            } else {
                self.startVirtualMachine()
            }
        })
    }
#endif

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        AppDelegate.sharedInstance = self
#if arch(arm64)
        DispatchQueue.main.async { [self] in
            createVirtualMachine()
            virtualMachineResponder = MacOSVirtualMachineDelegate()
            virtualMachine.delegate = virtualMachineResponder
            virtualMachineView.virtualMachine = virtualMachine
            virtualMachineView.capturesSystemKeys = true

            if #available(macOS 14.0, *) {
                // Configure the app to automatically respond to changes in the display size.
                virtualMachineView.automaticallyReconfiguresDisplay = true
            }

            if #available(macOS 14.0, *) {
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: saveFileURL.path) {
                    restoreVirtualMachine()
                } else {
                    startVirtualMachine()
                }
            } else {
                startVirtualMachine()
            }
        }
#endif
    }

    // MARK: Save the virtual machine when the app exits.

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
#if arch(arm64)
    @available(macOS 14.0, *)
    func saveVirtualMachine(completionHandler: @escaping () -> Void) {
        virtualMachine.saveMachineStateTo(url: saveFileURL, completionHandler: { (error) in
            guard error == nil else {
                fatalError("Virtual machine failed to save with \(error!)")
            }

            completionHandler()
        })
    }

    @available(macOS 14.0, *)
    func pauseAndSaveVirtualMachine(completionHandler: @escaping () -> Void) {
        virtualMachine.pause(completionHandler: { (result) in
            if case let .failure(error) = result {
                fatalError("Virtual machine failed to pause with \(error)")
            }

            self.saveVirtualMachine(completionHandler: completionHandler)
        })
    }
#endif

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
#if arch(arm64)
        if #available(macOS 14.0, *) {
            if virtualMachine.state == .running {
                pauseAndSaveVirtualMachine(completionHandler: {
                    sender.reply(toApplicationShouldTerminate: true)
                })
                
                return .terminateLater
            }
        }
#endif

        return .terminateNow
    }
    

    
    // MARK: - Programmatic Input Injection
    
    func injectClick(x: CGFloat, y: CGFloat) {
        // Convert coordinates to the view's coordinate system
        let viewPoint = CGPoint(x: x, y: virtualMachineView.bounds.height - y) // Flip Y coordinate
        
        // Create mouse events
        let mouseDownEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: viewPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )
        
        let mouseUpEvent = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: viewPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.05,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0.0
        )
        
        // Inject the events directly into the view
        DispatchQueue.main.async {
            if let mouseDown = mouseDownEvent {
                self.virtualMachineView.mouseDown(with: mouseDown)
                print("🖱️ Injected click at VM coordinates (\(Int(x)), \(Int(y)))")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let mouseUp = mouseUpEvent {
                    self.virtualMachineView.mouseUp(with: mouseUp)
                }
            }
        }
    }
    
    func injectRightClick(x: CGFloat, y: CGFloat) {
        let viewPoint = CGPoint(x: x, y: virtualMachineView.bounds.height - y)
        
        let rightMouseDownEvent = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: viewPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )
        
        let rightMouseUpEvent = NSEvent.mouseEvent(
            with: .rightMouseUp,
            location: viewPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.05,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0.0
        )
        
        DispatchQueue.main.async {
            if let mouseDown = rightMouseDownEvent {
                self.virtualMachineView.rightMouseDown(with: mouseDown)
                print("🖱️ Injected right-click at VM coordinates (\(Int(x)), \(Int(y)))")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let mouseUp = rightMouseUpEvent {
                    self.virtualMachineView.rightMouseUp(with: mouseUp)
                }
            }
        }
    }
    
    func injectKeyPress(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags = []) {
        let keyDownEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: NSPoint.zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
        
        let keyUpEvent = NSEvent.keyEvent(
            with: .keyUp,
            location: NSPoint.zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime + 0.05,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
        
        DispatchQueue.main.async {
            if let keyDown = keyDownEvent {
                self.virtualMachineView.keyDown(with: keyDown)
                print("⌨️ Injected key press: keyCode \(keyCode)")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let keyUp = keyUpEvent {
                    self.virtualMachineView.keyUp(with: keyUp)
                }
            }
        }
    }
    
    func injectText(_ text: String) {
        for char in text {
            if let keyCode = charToKeyCode(char) {
                let modifierFlags: NSEvent.ModifierFlags = char.isUppercase ? [.shift] : []
                injectKeyPress(keyCode: keyCode, modifierFlags: modifierFlags)
                usleep(50000) // 50ms delay between characters
            }
        }
        print("📝 Injected text: '\(text)'")
    }
    
    func charToKeyCode(_ char: Character) -> UInt16? {
        let lowercaseChar = char.lowercased().first!
        
        switch lowercaseChar {
        case "a": return 0x00
        case "b": return 0x0B
        case "c": return 0x08
        case "d": return 0x02
        case "e": return 0x0E
        case "f": return 0x03
        case "g": return 0x05
        case "h": return 0x04
        case "i": return 0x22
        case "j": return 0x26
        case "k": return 0x28
        case "l": return 0x25
        case "m": return 0x2E
        case "n": return 0x2D
        case "o": return 0x1F
        case "p": return 0x23
        case "q": return 0x0C
        case "r": return 0x0F
        case "s": return 0x01
        case "t": return 0x11
        case "u": return 0x20
        case "v": return 0x09
        case "w": return 0x0D
        case "x": return 0x07
        case "y": return 0x10
        case "z": return 0x06
        case " ": return 0x31
        case "1": return 0x12
        case "2": return 0x13
        case "3": return 0x14
        case "4": return 0x15
        case "5": return 0x17
        case "6": return 0x16
        case "7": return 0x1A
        case "8": return 0x1C
        case "9": return 0x19
        case "0": return 0x1D
        default: return nil
        }
    }
}

// MARK: - VMControlServer for CLI Communication

class VMControlServer {
    static let shared = VMControlServer()
    private var timer: Timer?
    
    func startListening() {
        // Create a simple file-based communication system
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.checkForCommands()
        }
        print("🎛️ VM Control Server started - listening for commands...")
    }
    
    private func checkForCommands() {
        let commandFile = NSTemporaryDirectory() + "vm_command.txt"
        
        if FileManager.default.fileExists(atPath: commandFile) {
            do {
                let command = try String(contentsOfFile: commandFile)
                try FileManager.default.removeItem(atPath: commandFile)
                processCommand(command.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                // Ignore errors - file might be being written to
            }
        }
    }
    
    private func processCommand(_ command: String) {
        guard let appDelegate = AppDelegate.sharedInstance else {
            print("❌ No app delegate available")
            return
        }
        
        // Parse commands
        if command.hasPrefix("click(") && command.hasSuffix(")") {
            let coords = String(command.dropFirst(6).dropLast(1))
            let parts = coords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) {
                appDelegate.injectClick(x: CGFloat(x), y: CGFloat(y))
            }
        }
        else if command.hasPrefix("rightclick(") && command.hasSuffix(")") {
            let coords = String(command.dropFirst(11).dropLast(1))
            let parts = coords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) {
                appDelegate.injectRightClick(x: CGFloat(x), y: CGFloat(y))
            }
        }
        else if command.hasPrefix("type('") && command.hasSuffix("')") {
            let text = String(command.dropFirst(6).dropLast(2))
            appDelegate.injectText(text)
        }
        else if command.hasPrefix("key('") && command.hasSuffix("')") {
            let keyName = String(command.dropFirst(5).dropLast(2))
            if let keyCode = keyNameToCode(keyName) {
                appDelegate.injectKeyPress(keyCode: keyCode)
            }
        }
        else if command.hasPrefix("cmd('") && command.hasSuffix("')") {
            let keyName = String(command.dropFirst(5).dropLast(2))
            if let keyCode = keyNameToCode(keyName) {
                appDelegate.injectKeyPress(keyCode: keyCode, modifierFlags: [.command])
            }
        }
    }
    
    private func keyNameToCode(_ keyName: String) -> UInt16? {
        switch keyName.lowercased() {
        case "enter", "return": return 0x24
        case "space": return 0x31
        case "escape", "esc": return 0x35
        case "tab": return 0x30
        case "delete", "backspace": return 0x33
        case "up": return 0x7E
        case "down": return 0x7D
        case "left": return 0x7B
        case "right": return 0x7C
        default: 
            if let char = keyName.first, let appDelegate = AppDelegate.sharedInstance {
                return appDelegate.charToKeyCode(char)
            }
            return nil
        }
    }
}
