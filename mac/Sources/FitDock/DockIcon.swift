import AppKit
import SwiftUI

/// Ícone do app (Finder, Itens de Início). Os números aparecem na barra de menus.
struct DockIconView: View {
    var steps: Int?
    var bpm: Int?
    var stale: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 92, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.11, green: 0.13, blue: 0.20),
                                              Color(red: 0.05, green: 0.06, blue: 0.10)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 92, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 3)
                )

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(Color(red: 0.35, green: 0.85, blue: 0.55))
                    Text("passos")
                        .font(.system(size: 40, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text(steps.map(Format.compactSteps) ?? "--")
                    .font(.system(size: 112, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 3)
                    .padding(.horizontal, 20)

                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.33))
                    Text(bpm.map(String.init) ?? "--")
                        .font(.system(size: 96, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("bpm")
                        .font(.system(size: 36, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
            .padding(.horizontal, 36)
        }
        .padding(50)
        .frame(width: 512, height: 512)
        .opacity(stale ? 0.55 : 1)
    }
}

@MainActor
enum DockIcon {
    static func render(_ view: DockIconView, scale: CGFloat = 2) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.nsImage
    }

    /// Usado pelo script de build para gerar o AppIcon.icns.
    static func writePNG(to path: String, size: Int) -> Bool {
        let scale = CGFloat(size) / 512
        guard let image = render(DockIconView(steps: 8432, bpm: 72, stale: false), scale: scale),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
