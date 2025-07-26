#!/bin/bash

echo "macOS Virtual Machine Launcher (with CGEvent Automation)"
echo "========================================================"

# Check if VM.bundle exists and has required files
if [ ! -d "$HOME/VM.bundle" ]; then
    echo "❌ VM.bundle not found in home directory"
    echo "Please run the InstallationTool first to create the VM"
    exit 1
fi

if [ ! -f "$HOME/VM.bundle/Disk.img" ] || [ ! -f "$HOME/VM.bundle/HardwareModel" ] || [ ! -f "$HOME/VM.bundle/MachineIdentifier" ]; then
    echo "❌ VM installation appears incomplete"
    echo "Required files missing in VM.bundle"
    exit 1
fi

echo "✅ VM.bundle found and appears complete"

# Check if InstallationTool is still running
if pgrep -f "InstallationTool" > /dev/null; then
    echo "⚠️  InstallationTool is still running"
    echo "Please wait for the installation to complete before launching the VM"
    exit 1
fi

echo "🚀 Launching macOS Virtual Machine with built-in CGEvent automation..."
echo ""
echo "🤖 Automation Features:"
echo "   • Automatically opens Finder after VM starts (5 seconds)"
echo "   • Built-in CGEvent controller for programmatic interaction"
echo "   • Smart coordinate conversion from VM space to screen space"
echo "   • Mouse clicks, keyboard events, and text typing capabilities"
echo ""

# Launch the VM app with CGEvent automation built-in
/Users/atul/Library/Developer/Xcode/DerivedData/macOSVirtualMachineSampleApp-gmzgycuzfrjlczdhyfheebsnxydz/Build/Products/Release/macOSVirtualMachineSampleApp.app/Contents/MacOS/macOSVirtualMachineSampleApp
