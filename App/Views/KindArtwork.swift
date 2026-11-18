import ConvetaKit
import SwiftUI

/// Conveta's own artwork for each kind of file: a small lit object on a coloured tile.
/// Drawn in code so it stays sharp at every size, from 16 pt rows to the 64 pt empty state.
struct KindArtwork: View {
    let kind: MediaKind?
    var size: CGFloat = Theme.rowThumbnail

    var body: some View {
        ZStack {
            Tile(color: kind.map(Theme.color(for:)) ?? .gray, size: size)
            Group {
                switch kind {
                case .video: VideoObject(size: size)
                case .audio: AudioObject(size: size)
                case .image: ImageObject(size: size)
                case .document: DocumentObject(size: size)
                case nil: UnknownObject(size: size)
                }
            }
            .shadow(color: .black.opacity(0.28), radius: size * 0.035, y: size * 0.03)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The rounded tile: lit from above, a glossy rim, and a soft shadow underneath.
private struct Tile: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        shape
            .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.28), color, color.mix(with: .black, by: 0.22)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                // A sheen across the upper half, like light on a curved surface.
                shape.fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0)], startPoint: .top, endPoint: .center))
                    .mask(Ellipse().frame(width: size * 1.5, height: size).offset(y: -size * 0.42))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05), .black.opacity(0.15)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: max(0.5, size * 0.02))
            }
            .shadow(color: color.mix(with: .black, by: 0.4).opacity(0.35), radius: size * 0.05, y: size * 0.04)
    }
}

/// White surfaces share one gentle top-to-bottom shading.
private let paper = LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom)

private struct VideoObject: View {
    let size: CGFloat

    var body: some View {
        let width = size * 0.64, height = size * 0.46
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(paper)
            // Film perforations along the top and bottom edges.
            VStack {
                Perforations(count: 5, size: size)
                Spacer()
                Perforations(count: 5, size: size)
            }
            .padding(.vertical, size * 0.035)
            PlayTriangle()
                .fill(LinearGradient(colors: [Theme.color(for: .video).mix(with: .white, by: 0.2), Theme.color(for: .video).mix(with: .black, by: 0.25)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.17, height: size * 0.19)
                .offset(x: size * 0.015)
                .shadow(color: .black.opacity(0.25), radius: size * 0.012, y: size * 0.01)
        }
        .frame(width: width, height: height)
        .rotation3DEffect(.degrees(12), axis: (x: 1, y: -0.4, z: 0), perspective: 0.6)
    }
}

private struct Perforations: View {
    let count: Int
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.05) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: size * 0.01)
                    .fill(Theme.color(for: .video).opacity(0.35))
                    .frame(width: size * 0.06, height: size * 0.035)
            }
        }
    }
}

nonisolated private struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A vinyl record tilted toward the light: grooves, a label in the audio colour, and a highlight sweep.
private struct AudioObject: View {
    let size: CGFloat

    var body: some View {
        let disc = size * 0.66
        let accent = Theme.color(for: .audio)
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.24), Color(white: 0.08)], center: .center, startRadius: 0, endRadius: disc / 2))
            // Grooves: fine rings that catch a little light.
            ForEach([0.92, 0.8, 0.68, 0.56], id: \.self) { scale in
                Circle()
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: max(0.4, size * 0.008))
                    .frame(width: disc * scale, height: disc * scale)
            }
            // The light sweeping across the surface.
            Circle()
                .fill(AngularGradient(colors: [.clear, .white.opacity(0.32), .clear, .clear, .white.opacity(0.18), .clear, .clear],
                                      center: .center, angle: .degrees(-30)))
            Circle()
                .fill(LinearGradient(colors: [accent.mix(with: .white, by: 0.25), accent.mix(with: .black, by: 0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: disc * 0.38, height: disc * 0.38)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: max(0.4, size * 0.008)))
            Circle()
                .fill(Color(white: 0.1))
                .frame(width: disc * 0.07, height: disc * 0.07)
        }
        .frame(width: disc, height: disc)
        .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom),
                                       lineWidth: max(0.5, size * 0.012)))
    }
}

private struct ImageObject: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            PhotoCard(size: size, sky: [Color(white: 0.92), Color(white: 0.8)], showsScene: false)
                .rotationEffect(.degrees(10))
                .offset(x: size * 0.06, y: -size * 0.03)
            PhotoCard(size: size, sky: [Color(red: 0.62, green: 0.88, blue: 1.0), Color(red: 0.86, green: 0.96, blue: 1.0)], showsScene: true)
                .rotationEffect(.degrees(-7))
                .offset(x: -size * 0.03, y: size * 0.02)
        }
    }
}

private struct PhotoCard: View {
    let size: CGFloat
    let sky: [Color]
    let showsScene: Bool

    var body: some View {
        let inset = size * 0.04
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.05, style: .continuous).fill(paper)
            ZStack(alignment: .bottom) {
                LinearGradient(colors: sky, startPoint: .top, endPoint: .bottom)
                if showsScene {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.3), Color(red: 1, green: 0.62, blue: 0.1)], startPoint: .top, endPoint: .bottom))
                        .frame(width: size * 0.1, height: size * 0.1)
                        .offset(x: size * 0.1, y: -size * 0.2)
                    Mountains()
                        .fill(LinearGradient(colors: [Theme.color(for: .image).mix(with: .white, by: 0.1), Theme.color(for: .image).mix(with: .black, by: 0.35)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: size * 0.2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.025, style: .continuous))
            .padding(inset)
        }
        .frame(width: size * 0.52, height: size * 0.46)
    }
}

nonisolated private struct Mountains: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.45))
        path.addLine(to: CGPoint(x: rect.width * 0.3, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.width * 0.55, y: rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.7))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct DocumentObject: View {
    let size: CGFloat

    var body: some View {
        let fold = size * 0.14
        ZStack(alignment: .topTrailing) {
            FoldedPage(fold: fold).fill(paper)
            // The folded corner, shaded so it lifts off the page.
            FoldCorner()
                .fill(LinearGradient(colors: [Color(white: 0.72), Color(white: 0.95)], startPoint: .bottomLeading, endPoint: .topTrailing))
                .frame(width: fold, height: fold)
                .shadow(color: .black.opacity(0.2), radius: size * 0.01, x: -size * 0.005, y: size * 0.008)
            VStack(alignment: .leading, spacing: size * 0.04) {
                RoundedRectangle(cornerRadius: size * 0.012).fill(Theme.color(for: .document)).frame(width: size * 0.2, height: size * 0.05)
                ForEach([0.34, 0.3, 0.34, 0.22], id: \.self) { width in
                    Capsule().fill(Color(white: 0.72)).frame(width: size * width, height: size * 0.03)
                }
            }
            .padding(.leading, size * 0.07)
            .padding(.top, size * 0.1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: size * 0.48, height: size * 0.6)
        .rotationEffect(.degrees(-4))
    }
}

nonisolated private struct FoldedPage: Shape {
    let fold: CGFloat
    func path(in rect: CGRect) -> Path {
        let radius = rect.width * 0.08
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

nonisolated private struct FoldCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.12), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct UnknownObject: View {
    let size: CGFloat

    var body: some View {
        Text("?")
            .font(.system(size: size * 0.46, weight: .heavy, design: .rounded))
            .foregroundStyle(paper)
    }
}
