macOS Virtual Machine Setup Guide
Prerequisites

Xcode installed
macOS IPSW file downloaded

Setup Instructions
1. Clean Previous Build (if exists)
bashrm -rf ~/VM.bundle


2. Build the Installation Tool
bashxcodebuild -project macOSVirtualMachineSampleApp.xcodeproj \
  -scheme InstallationTool-Swift \
  -configuration Release \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_ENTITLEMENTS="InstallationTool.entitlements" \
  build


3. Create VM Bundle
Download IPSW file from apple
Replace [PATH_TO_IPSW] with your macOS IPSW file path:
bash[PATH_TO_DERIVED_DATA]/Build/Products/Release/InstallationTool-Swift [PATH_TO_IPSW]

To find your DerivedData path:
bashxcodebuild -showBuildSettings | grep DERIVED_DATA_DIR


4. Build the VM Application

bashxcodebuild -project macOSVirtualMachineSampleApp.xcodeproj \
  -scheme macOSVirtualMachineSampleApp-Swift \
  -configuration Release \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_ENTITLEMENTS="macOSVirtualMachineSampleApp.entitlements" \
  build


5. Launch the VM
bash./launch_vm.sh



Setting Up Shared Folder (Inside VM)
Once the VM is running, you can mount the host shared folder:
1. Create Mount Point
bashsudo mkdir -p /Volumes/HostShared
2. Mount Shared Folder
bashsudo mount -t virtiofs vm-shared /Volumes/HostShared


3. Auto-mount on Boot (Optional)
Add to /etc/fstab:
vm-shared /Volumes/HostShared virtiofs rw,nofail 0 0



Once on the VM. Copy .dmg disk file to the shared dir and reupload using Carbon Copy Creator 


## Programmatic VM Controls

This project includes several tools for programmatically controlling the VM:

### VM Control CLI
Use the interactive command-line interface to control the VM:

```bash
swift vm_control.swift
```

Available commands:
- `click(x,y)` - Left click at coordinates
- `rightclick(x,y)` - Right click at coordinates  
- `type('text')` - Type text into the VM
- `key('name')` - Press keys (enter, space, escape, up, down, left, right)
- `cmd('key')` - Press Cmd+key combinations
- `help` - Show available commands
- `quit` - Exit the CLI

### AI Agent
Launch the AI-powered VM assistant:

```bash
# Set your OpenAI API key
export OPENAI_API_KEY="your-api-key-here"

# Launch the AI agent
./launch_ai_agent.sh
```

The AI agent can:
- Take screenshots of the VM
- Analyze the current state
- Execute commands automatically
- Provide intelligent assistance

### VM Control Server
The VM automatically starts a control server that listens for commands. You can also use the underlying Swift classes directly in your own code:

```swift
// Example usage
let controller = VMRemoteController()
controller.sendCommand("click(100,200)")
controller.sendCommand("type('Hello VM!')")
```

### Launch Scripts
- `./launch_vm.sh` - Start the VM application
- `./launch_ai_agent.sh` - Start the AI agent with VM controls

**Note:** Make sure the VM is running before using the control tools.