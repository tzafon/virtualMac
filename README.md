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