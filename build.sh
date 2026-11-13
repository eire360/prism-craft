#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p 'build/Prism Craft.app/Contents/MacOS' work/swift-cache
swiftc Source/*.swift -O -target arm64-apple-macosx14.0 -module-cache-path "$PWD/work/swift-cache" -framework Cocoa -framework SwiftUI -framework SceneKit -framework AVFoundation -framework Vision -framework Metal -o 'build/Prism Craft.app/Contents/MacOS/PrismCraft'
cp Info.plist 'build/Prism Craft.app/Contents/Info.plist'
codesign --force --sign - 'build/Prism Craft.app'
print 'Built build/Prism Craft.app'
