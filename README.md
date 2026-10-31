# Fauxjitsu Scan Buddy

A native Apple Silicon menu bar app for the Fujitsu ScanSnap S1500. Press Scan on the
scanner, choose options (the last-used ones are preselected), and press Scan again or Return.

## Build and install

Requires the Command Line Tools and `brew install sane-backends`, which stays a runtime
dependency: the app links Homebrew's `libsane`.

    scripts/build-app.sh --install    # builds, copies to ~/Applications, launches
    scripts/test.sh

The code and package still use the working name `ScanButton`. `scripts/make-icon.sh`
regenerates `App/AppIcon.icns` from the mascot view.

## Fixed scan settings

300 dpi, Letter size, both sides with blank sides dropped. These are constants in
`Sources/ScanKit/SaneScanner.swift`.

## How it works

- **Button:** polls the `scan` SANE sensor every 150 ms while the scanner is on USB. IOKit
  notifications stop the polling when the cover closes. The S1500 latches a press until it
  is read, so a quick tap isn't missed.
- **SANE:** the app loads only the `fujitsu` backend. That cuts startup from about 4 s to
  0.03 s and keeps the network backends off the LAN.
- **OCR and PDF:** Apple Vision and CoreGraphics, with an invisible text layer over the image.

## Troubleshooting

The app holds the scanner open, so quit it before using `scanimage` or ScanSnap Manager.
`scan-check` tests the hardware without the app (`swift build`, then find it with
`swift build --show-bin-path`):

    scan-check watch 30
    scan-check scan ~/Desktop bw ocr pdf

## License

MIT; see `LICENSE`. The app links [SANE](http://www.sane-project.org)'s `libsane` at runtime (GPL
with the SANE linking exception), which uses `libusb` (LGPL). Neither is included in this repository.

This is an independent project, not affiliated with or endorsed by Fujitsu, PFU or Ricoh.
