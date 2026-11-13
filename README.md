# Prism Craft

Custom Minecraft bridge mod and Mac companion using head/face tracking for aiming and hand gestures for movement, inventory and gameplay controls.

## Download

[Download source ZIP](https://github.com/eire360/prism-craft/archive/refs/heads/main.zip)

## Setup

Requires macOS, a camera, and compatible Minecraft/Fabric.

- `Source/`: Mac camera/gesture companion.
- `Bridge/`: Minecraft Fabric mod.

Build the Mac companion on an Apple Silicon Mac with Apple developer command-line tools:

```sh
./build.sh
open "build/Prism Craft.app"
```

Start its camera, allow camera access, enable Send to Minecraft, and press F8 in a single-player world to arm the controls. The Fabric bridge must also be compiled for the matching game version and placed in that instance’s mods folder; the bridge build is not automated by this script.

## Controls

Turn your head to steer, use the two-hand wheel for movement, a right fist to mine, and a left thumbs-up to open/close inventory. Press F8 to disable the game bridge.
