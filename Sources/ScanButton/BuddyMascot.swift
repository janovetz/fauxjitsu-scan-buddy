import SwiftUI

/// The app's mascot: a friendly scanner with a page in its feeder. It scales to any size, and
/// scripts/make-icon draws the app icon from this same view.
struct BuddyMascot: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                paper(side)
                scannerBody(side)
                face(side)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func paper(_ side: CGFloat) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: side * 0.03)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: side * 0.03)
                .stroke(Color(white: 0.6), lineWidth: max(side * 0.012, 0.5))
            VStack(spacing: side * 0.045) {
                ForEach(0..<2, id: \.self) { _ in
                    Rectangle()
                        .fill(Color(white: 0.65))
                        .frame(height: max(side * 0.022, 0.5))
                }
            }
            .padding(.horizontal, side * 0.07)
            .padding(.top, side * 0.07)
        }
        .frame(width: side * 0.56, height: side * 0.5)
        .offset(y: -side * 0.24)
    }

    private func scannerBody(_ side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: side * 0.15)
            .fill(LinearGradient(
                colors: [Color(red: 0.2, green: 0.72, blue: 0.82), Color(red: 0.07, green: 0.42, blue: 0.68)],
                startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) {
                // The feed slot, which the page disappears into.
                Capsule()
                    .fill(Color(red: 0.03, green: 0.2, blue: 0.34))
                    .frame(width: side * 0.68, height: side * 0.035)
                    .padding(.top, side * 0.05)
            }
            .frame(width: side * 0.92, height: side * 0.66)
            .offset(y: side * 0.16)
    }

    private func face(_ side: CGFloat) -> some View {
        ZStack {
            eye(side).offset(x: -side * 0.17)
            eye(side).offset(x: side * 0.17)
            Smile()
                .stroke(Color.white, style: StrokeStyle(lineWidth: side * 0.04, lineCap: .round))
                .frame(width: side * 0.2, height: side * 0.1)
                .offset(y: side * 0.17)
        }
        .offset(y: side * 0.14)
    }

    private func eye(_ side: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color.white).frame(width: side * 0.19, height: side * 0.19)
            Circle().fill(Color(white: 0.1)).frame(width: side * 0.1, height: side * 0.1)
                .offset(x: side * 0.015, y: -side * 0.012)
        }
    }
}

private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        return path
    }
}
