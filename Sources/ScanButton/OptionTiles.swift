import ScanKit
import SwiftUI

/// A large, labeled, click-anywhere choice in the options panel.
struct OptionTile<Icon: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                icon
                Text(title)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(width: 84, height: 96)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Icons

/// A sheet of paper with a folded corner. It stays white in dark mode, like real paper.
struct PageIcon<Content: View>: View {
    @ViewBuilder let content: Content

    private static var size: CGSize { CGSize(width: 50, height: 64) }

    var body: some View {
        ZStack {
            PageOutline().fill(Color.white)
            content
                .padding(.horizontal, 5)
                .padding(.top, 12)
                .padding(.bottom, 5)
                .frame(width: Self.size.width, height: Self.size.height)
            PageOutline().stroke(Color.gray, lineWidth: 1)
            PageFold().fill(Color(white: 0.85))
            PageFold().stroke(Color.gray, lineWidth: 1)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
    }
}

private let foldSize: CGFloat = 11

private struct PageOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - foldSize, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + foldSize))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PageFold: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX - foldSize, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - foldSize, y: rect.minY + foldSize))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + foldSize))
        path.closeSubpath()
        return path
    }
}

private struct Mountain: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.width * 0.62, y: rect.height * 0.68))
        path.addLine(to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.5))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A small landscape picture.
private struct PictureMark: View {
    let sky: Color
    let sun: Color
    let land: Color
    var border = Color.clear

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle().fill(sky)
            Circle().fill(sun).frame(width: 8, height: 8).padding(3)
            Mountain().fill(land)
        }
        .overlay(Rectangle().stroke(border, lineWidth: 1))
        .frame(height: 22)
    }
}

private struct TextLines: View {
    let color: Color
    var count = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<count, id: \.self) { index in
                Rectangle()
                    .fill(color)
                    .frame(height: 2)
                    .padding(.trailing, index == count - 1 ? 12 : 0)
            }
        }
    }
}

struct ColorModeIcon: View {
    let mode: ColorMode

    var body: some View {
        PageIcon {
            VStack(spacing: 5) {
                switch mode {
                case .blackAndWhite:
                    PictureMark(sky: .white, sun: .black, land: .black, border: .black)
                    TextLines(color: .black)
                case .grayscale:
                    PictureMark(sky: Color(white: 0.8), sun: Color(white: 0.97), land: Color(white: 0.42))
                    TextLines(color: Color(white: 0.45))
                case .color:
                    PictureMark(sky: Color(red: 0.35, green: 0.68, blue: 0.98), sun: .yellow, land: Color(red: 0.2, green: 0.68, blue: 0.3))
                    TextLines(color: Color(red: 0.85, green: 0.2, blue: 0.25))
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct OCRIcon: View {
    let isOn: Bool

    var body: some View {
        PageIcon {
            ZStack {
                Text("Aa")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(isOn ? Color.black : Color(white: 0.55))
                if isOn {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(Color.blue)
                } else {
                    Capsule()
                        .fill(Color.red)
                        .frame(width: 42, height: 3.5)
                        .rotationEffect(.degrees(-45))
                }
            }
        }
    }
}

struct FormatIcon: View {
    let format: OutputFormat

    var body: some View {
        PageIcon {
            VStack(spacing: 4) {
                switch format {
                case .pdf:
                    TextLines(color: Color(white: 0.5), count: 4)
                    Spacer(minLength: 0)
                    badge("PDF", color: Color(red: 0.82, green: 0.13, blue: 0.13))
                case .jpg:
                    PictureMark(sky: Color(red: 0.35, green: 0.68, blue: 0.98), sun: .yellow, land: Color(red: 0.2, green: 0.68, blue: 0.3))
                    Spacer(minLength: 0)
                    badge("JPG", color: Color(red: 0.1, green: 0.4, blue: 0.8))
                }
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 1)
            .background(color)
    }
}
