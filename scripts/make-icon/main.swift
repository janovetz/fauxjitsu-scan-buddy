// Writes an iconset of the mascot to the directory given as the first argument.
// Run through scripts/make-icon.sh.
import AppKit
import SwiftUI

struct AppIcon: View {
    var body: some View {
        // Apple's icon grid: an 824pt rounded square centered on a 1024pt canvas.
        RoundedRectangle(cornerRadius: 185, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.99, green: 0.97, blue: 0.9), Color(red: 0.93, green: 0.86, blue: 0.72)],
                startPoint: .top, endPoint: .bottom))
            .overlay(BuddyMascot().padding(95))
            .frame(width: 824, height: 824)
            .frame(width: 1024, height: 1024)
    }
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1])

MainActor.assumeIsolated {
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let renderer = ImageRenderer(content: AppIcon())
            renderer.scale = CGFloat(points * scale) / 1024
            guard let image = renderer.cgImage else { fatalError("Could not render the icon") }
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            let suffix = scale == 2 ? "@2x" : ""
            try! png.write(to: directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        }
    }
}
