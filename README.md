# Ornata Lights

A small native macOS menu bar app for the lighting on a **Razer Ornata V2** keyboard, since Razer Synapse doesn't run on macOS.

<img src="docs/screenshot.png" width="380" alt="The Ornata Lights panel">

- 24 live per-key animations: rainbow, rain, fire, aurora, plasma, snake, tetris, pong, fireworks, a clock, a CPU meter and more
- Effects stored in the keyboard itself: solid colour, gradient, breathing, light-up-as-you-type, spectrum, wave
- Brightness, start at login, and it restores the last effect when it starts

## Build

Needs Xcode (or its command line tools) on an Apple Silicon Mac running macOS 14 or later.

```sh
./build.sh
```

This compiles the app, signs it ad hoc and installs it as `~/Applications/Ornata Lights.app`, quitting the running copy first.

Opening the app from Finder or Spotlight shows its window; it also lives in the menu bar (keyboard icon). If the menu bar is full, the notch can hide the icon.

## How it talks to the keyboard

Every command is a 90-byte HID feature report (`SET_REPORT`) sent to USB interface 2. The byte layout comes from the [openrazer](https://github.com/openrazer/openrazer) Linux driver (`razerkbd_driver.c`, `razerchromacommon.c`).

macOS won't let an app open a keyboard's HID interfaces, so `OrnataUSB.c` sends the report as a USB control request to the device through IOKit instead. That needs no permissions and no drivers, the same trick as [Razer macOS](https://github.com/1kc/razer-macos).

The keyboard drops packets sent back to back, so there's a 5 ms pause after each one. A per-key frame is 7 packets, so animations run at about 28 fps.

| File | What it does |
| --- | --- |
| `Sources/OrnataUSB.c` | Finds the keyboard and sends reports over IOKit |
| `Sources/Protocol.swift` | Builds the reports: effects, brightness, per-key frames |
| `Sources/Effects.swift` | The animations, one class each |
| `Sources/Lights.swift` | Owns the keyboard: commands, the animation thread, saved state |
| `Sources/ControlPanel.swift` | The SwiftUI panel, used in the menu bar and the window |
| `Sources/App.swift` | App entry point, window handling |

`docs/screenshot.png` is made by the app itself:

```sh
~/Applications/Ornata\ Lights.app/Contents/MacOS/Ornata\ Lights --snapshot docs/screenshot.png
```

## Other Razer keyboards

Only the Ornata V2 (`1532:025D`) is wired up. Many newer Razer keyboards use the same extended protocol with a different product ID, matrix size or USB interface; openrazer's driver lists them.
