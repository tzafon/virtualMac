#!/usr/bin/env swift

import Foundation
import Cocoa

class VMRemoteController {
    private let commandFile = NSTemporaryDirectory() + "vm_command.txt"
    
    func sendCommand(_ command: String) {
        do {
            try command.write(toFile: commandFile, atomically: true, encoding: .utf8)
            print("✅ Sent command: \(command)")
        } catch {
            print("❌ Failed to send command: \(error)")
        }
    }
    
    func isVMRunning() -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        return apps.contains { $0.localizedName?.contains("macOSVirtualMachineSampleApp") == true }
    }
}

// MARK: - Interactive CLI
print("🖥️  VM Remote Controller CLI")
print("============================")
print("Commands:")
print("  click(x,y)      - Left click at coordinates")
print("  rightclick(x,y) - Right click at coordinates") 
print("  type('text')    - Type text")
print("  key('name')     - Press key (enter, space, escape, up, down, left, right)")
print("  cmd('key')      - Press Cmd+key")
print("  quit            - Exit CLI")
print("  help            - Show this help")
print("")

let controller = VMRemoteController()

// Check if VM is running
if !controller.isVMRunning() {
    print("⚠️  VM app not running. Please start the VM first.")
    print("   Run: ./launch_vm.sh")
    exit(1)
}

print("✅ VM app detected - ready for commands!")
print("")

while true {
    print("vm> ", terminator: "")
    
    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        continue
    }
    
    if input.isEmpty { continue }
    
    switch input.lowercased() {
    case "quit", "exit", "q":
        print("👋 Goodbye!")
        exit(0)
        
    case "help", "h":
        print("Commands:")
        print("  click(x,y)      - Left click at coordinates")
        print("  rightclick(x,y) - Right click at coordinates")
        print("  type('text')    - Type text")
        print("  key('name')     - Press key (enter, space, escape, up, down, left, right)")
        print("  cmd('key')      - Press Cmd+key")
        print("  quit            - Exit CLI")
        continue
        
    default:
        // Validate and send command
        let validCommands = ["click(", "rightclick(", "type('", "key('", "cmd('"]
        let isValid = validCommands.contains { input.hasPrefix($0) }
        
        if isValid {
            controller.sendCommand(input)
            usleep(100000) // 100ms delay to allow processing
        } else {
            print("❌ Invalid command. Type 'help' for available commands.")
        }
    }
}
