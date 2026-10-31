# Fauxjitsu Scan Buddy

Native Apple Silicon menu bar app for the Fujitsu ScanSnap S1500. Pressing the scanner's button
opens an options panel; the scan is saved as a PDF (optionally with OCR) or as JPGs.

## Commands

    scripts/test.sh                   # run the tests; use this rather than plain `swift test`
    scripts/build-app.sh --install    # build, copy to ~/Applications, relaunch
    scripts/make-icon.sh              # regenerate App/AppIcon.icns after changing the mascot
    swift build && "$(swift build --show-bin-path)/scan-check" watch 30    # hardware check

Only the Command Line Tools are assumed, not Xcode, so there is no `.xcodeproj` and `xcodebuild`
is unavailable. `brew install sane-backends` is needed to build and to run.

## Layout

- `Sources/CSane`: system library wrapper for Homebrew's `libsane`.
- `Sources/ScanKit`: scanner access, OCR and file output, with no UI.
- `Sources/ScanButton`: the AppKit and SwiftUI menu bar app.
- `Sources/scan-check`: command line tool for testing the hardware without the app.
- `Tests/ScanKitTests`: Swift Testing tests of the output pipeline, which need no scanner.

The code, package, process and bundle ID use the old working name `ScanButton`; only user-facing
text says Fauxjitsu Scan Buddy.

## Things that aren't obvious

- SANE isn't thread-safe. All SANE calls go through `ScannerMonitor`'s serial queue, and a running
  job deliberately blocks button polling.
- The S1500 latches a button press until it's read and reports it once, however long the button is
  held. `isScanButtonPressed()` therefore consumes the press.
- The app writes a one-line `dll.conf` and sets `SANE_CONFIG_DIR` so that only the `fujitsu` backend
  loads. The default config takes about 4 s to start and has network backends probing the LAN.
- The app holds the device open while running, so `scanimage` and `scan-check` can't reach the
  scanner until it quits.
- The USB watcher matches only the S1500's vendor and product IDs (`0x04C5`, `0x11A2`).
- Check that the output folder is usable before feeding paper, and keep pages already scanned if the
  feed fails partway. Neither failure should cost the user a stack of scanned paper.

## Testing

Automated tests use generated pages. Anything touching the feeder or button needs the real scanner,
and running a scan feeds whatever paper is in the hopper, so check with the user first.

## Licensing

The project is MIT. It links `libsane` (GPL with the SANE linking exception) at runtime, and
`libsane` uses `libusb` (LGPL). Neither is included in the repo. Bundling them into a distributed
app would add obligations to ship their licenses and offer their source.
