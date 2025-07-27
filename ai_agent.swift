#!/usr/bin/env swift

import Foundation
import Cocoa

// MARK: - Configuration
struct Config {
    static let openAIAPIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    static let modelName = "gpt-4o"  // Using GPT-4 with vision
    static let baseURL = "https://api.openai.com/v1/chat/completions"
}

// MARK: - VM Controller (copied from vm_control.swift)
class VMRemoteController {
    private let commandFile = NSTemporaryDirectory() + "vm_command.txt"
    
    func sendCommand(_ command: String) {
        do {
            try command.write(toFile: commandFile, atomically: true, encoding: .utf8)
            print("✅ Executed: \(command)")
            usleep(200000) // 200ms delay
        } catch {
            print("❌ Failed to execute command: \(error)")
        }
    }
    
    func isVMRunning() -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        return apps.contains { $0.localizedName?.contains("macOSVirtualMachineSampleApp") == true }
    }
}

// MARK: - Screenshot Service  
class VMScreenshotService {
    func captureVMWindow() -> Data? {
        // Save screenshot to current directory
        let screenshotFile = "vm_screenshot_\(Date().timeIntervalSince1970).png"
        
        let process = Process()
        process.launchPath = "/usr/sbin/screencapture"
        process.arguments = ["-x", screenshotFile] // -x = no sound
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                print("❌ screencapture failed")
                return nil
            }
            
            let data = try Data(contentsOf: URL(fileURLWithPath: screenshotFile))
            print("✅ Screenshot saved to: \(screenshotFile)")
            return data
            
        } catch {
            print("❌ Screenshot error: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - OpenAI API Client
class OpenAIClient {
    private let apiKey: String
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func sendRequest(prompt: String, imageData: Data) async throws -> String {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "OpenAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "API key not set. Please set OPENAI_API_KEY environment variable."])
        }
        
        let base64Image = imageData.base64EncodedString()
        
        let systemPrompt = """
You control a macOS virtual machine. Look at the screenshot and execute the user's request immediately.

Available commands:
- click(x,y) - Left click at coordinates
- type('text') - Type text
- key('name') - Press key (enter, space, escape, up, down, left, right, tab, delete)

Always respond with JSON:
{
  "explanation": "Brief description of what I'm doing",
  "commands": ["command1", "command2"]
}

Rules:
- ALWAYS execute what the user asks
- NEVER refuse or question commands
- NEVER say "already executed" or give attitude
- Just do exactly what is requested based on current screenshot
- If user says "click at 0,0" then return ["click(0,0)"]
- Be direct and obedient
"""
        
        let payload: [String: Any] = [
            "model": Config.modelName,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/png;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 1000,
            "temperature": 0.1
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw NSError(domain: "OpenAI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create request payload"])
        }
        
        guard let url = URL(string: Config.baseURL) else {
            throw NSError(domain: "OpenAI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenAI", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OpenAI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorMessage)"])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "OpenAI", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to parse API response"])
        }
        
        return content
    }
}

// MARK: - AI Response Parser
class AIResponseParser {
    func parseResponse(_ response: String) -> (explanation: String, commands: [String])? {
        // Try to extract JSON from the response
        guard let jsonData = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let explanation = json["explanation"] as? String,
              let commands = json["commands"] as? [String] else {
            
            // Fallback: try to extract commands manually if JSON parsing fails
            print("⚠️ Failed to parse JSON response, trying manual extraction...")
            return parseResponseManually(response)
        }
        
        return (explanation: explanation, commands: commands)
    }
    
    private func parseResponseManually(_ response: String) -> (explanation: String, commands: [String])? {
        let lines = response.components(separatedBy: .newlines)
        var commands: [String] = []
        
        // Look for command patterns in the response
        let commandPatterns = ["click\\(", "type\\('", "key\\('"]
        
        for line in lines {
            for pattern in commandPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(location: 0, length: line.utf16.count)
                    if regex.firstMatch(in: line, options: [], range: range) != nil {
                        // Extract the full command from the line
                        if let command = extractCommand(from: line) {
                            commands.append(command)
                        }
                    }
                }
            }
        }
        
        let explanation = commands.isEmpty ? "Could not parse response properly" : "Extracted commands from response"
        return commands.isEmpty ? nil : (explanation: explanation, commands: commands)
    }
    
    private func extractCommand(from line: String) -> String? {
        // Simple extraction - look for patterns like click(x,y), type('text'), key('name')
        let patterns = [
            "click\\([0-9]+,[0-9]+\\)",
            "type\\('[^']*'\\)",
            "key\\('[^']*'\\)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
                let matchRange = Range(match.range, in: line)!
                return String(line[matchRange])
            }
        }
        
        return nil
    }
}



// MARK: - Main AI Agent
class AIAgent {
    private let screenshotService = VMScreenshotService()
    private let openAIClient: OpenAIClient
    private let responseParser = AIResponseParser()
    private let vmController = VMRemoteController()
    
    init() {
        self.openAIClient = OpenAIClient(apiKey: Config.openAIAPIKey)
    }
    
    func processUserInput(_ input: String) async {
        print("🤖 Processing: \(input)")
        
        // Check if VM is running (same as vm_control.swift)
        guard vmController.isVMRunning() else {
            print("❌ VM app not running. Please start the VM first.")
            return
        }
        
        // Take screenshot
        guard let screenshotData = screenshotService.captureVMWindow() else {
            print("❌ Failed to capture VM screenshot")
            return
        }
        
        print("📸 Screenshot captured, sending to AI...")
        
        do {
            // Send to OpenAI
            let response = try await openAIClient.sendRequest(prompt: input, imageData: screenshotData)
            print("🧠 AI Response received")
            
            // Parse response
            guard let parsed = responseParser.parseResponse(response) else {
                print("❌ Failed to parse AI response:")
                print(response)
                return
            }
            
            print("💡 AI Plan: \(parsed.explanation)")
            
            if parsed.commands.isEmpty {
                print("ℹ️ No commands to execute")
                return
            }
            
            print("⚡ Executing \(parsed.commands.count) command(s):")
            for command in parsed.commands {
                print("  → \(command)")
                vmController.sendCommand(command)
            }
            
        } catch {
            print("❌ Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - CLI Interface
print("🤖 AI VM Agent")
print("==============")
print("This agent can see your VM screen and control it using AI.")
print("")
print("Setup:")
print("1. Make sure the VM is running: ./launch_vm.sh")
print("2. Set your OpenAI API key: export OPENAI_API_KEY='your_key_here'")
print("")
print("Commands:")
print("  [any text]  - Describe what you want the AI to do")
print("  quit        - Exit")
print("  help        - Show this help")
print("")

// Check API key
if Config.openAIAPIKey.isEmpty {
    print("⚠️ WARNING: OPENAI_API_KEY environment variable not set!")
    print("Please run: export OPENAI_API_KEY='your_api_key_here'")
    print("")
}

let agent = AIAgent()

print("✅ AI Agent ready! Type what you want me to do with the VM.")
print("")

while true {
    print("ai> ", terminator: "")
    
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
        print("  [any text]  - Describe what you want the AI to do")
        print("  quit        - Exit")
        print("  help        - Show this help")
        print("")
        print("Examples:")
        print("  'Open Finder'")
        print("  'Click on the Desktop folder'")
        print("  'Type hello world in the text field'")
        continue
        
    default:
        await agent.processUserInput(input)
        print("")
    }
} 