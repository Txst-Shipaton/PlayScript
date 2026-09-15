import SwiftUI
import StoryCore

enum Palette {
    static let paper = Color(hex: 0xFCF5F0)
    static let ink = Color(hex: 0x492630)
    static let rose = Color(hex: 0x9D4057)
    static let muted = Color(hex: 0x80656B)
    static let blush = Color(hex: 0xF0DAD8)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

extension Mood {
    var background: Color {
        switch self {
        case .longing: Color(hex: 0x533740)
        case .tender: Color(hex: 0x8B515C)
        case .uneasy: Color(hex: 0x46424E)
        case .grief: Color(hex: 0x33313E)
        case .dawn: Color(hex: 0xB07B6C)
        }
    }

    var light: Color {
        switch self {
        case .longing: Color(hex: 0xAC7881)
        case .tender: Color(hex: 0xD9A099)
        case .uneasy: Color(hex: 0x99909D)
        case .grief: Color(hex: 0x777181)
        case .dawn: Color(hex: 0xF0C5A2)
        }
    }
}

struct GlassSurface: ViewModifier {
    var dark = false
    var radius: CGFloat = 26
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                if reduceTransparency {
                    shape.fill(dark ? Color(hex: 0x4D3942) : Palette.paper)
                } else {
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill(dark ? Color.black.opacity(0.24) : Color.white.opacity(0.24)))
                        .environment(\.colorScheme, dark ? .dark : .light)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(dark ? 0.3 : 0.65), lineWidth: 0.8)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func glass(dark: Bool = false, radius: CGFloat = 26) -> some View {
        modifier(GlassSurface(dark: dark, radius: radius))
    }

    func literary(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> some View {
        font(.custom("Georgia", size: size, relativeTo: style))
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct SmallLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .tracking(2.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A quiet, typographic holding treatment until commissioned illustrations arrive.
/// Each beat can replace this with a bundled asset via its `artwork` field.
struct SceneBackdrop: View {
    let mood: Mood
    var artwork: String? = nil
    var animationName: String? = nil
    var cover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                mood.background
                if let animationName {
                    AnimatedSceneBackdrop(name: animationName, reduceMotion: reduceMotion)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .id(animationName)
                        .overlay {
                            Rectangle().fill(mood.light.opacity(0.08)).blendMode(.softLight)
                        }
                } else if let artwork, UIImage(named: artwork) != nil {
                    Image(artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .overlay {
                            Rectangle().fill(mood.light.opacity(0.12)).blendMode(.softLight)
                        }
                } else {
                    // Editorial framing, intentionally not substitute scene art.
                    RoundedRectangle(cornerRadius: proxy.size.width / 2)
                        .fill(mood.light.opacity(0.18))
                        .padding(.horizontal, proxy.size.width * 0.14)
                        .padding(.top, cover ? 34 : 100)
                        .padding(.bottom, -80)
                    RoundedRectangle(cornerRadius: proxy.size.width / 2)
                        .stroke(mood.light.opacity(0.25), lineWidth: 1)
                        .padding(.horizontal, proxy.size.width * 0.14 + 9)
                        .padding(.top, cover ? 43 : 109)
                        .padding(.bottom, -70)
                    Text("R  &  J")
                        .font(.custom("Baskerville", size: cover ? 53 : 68))
                        .foregroundStyle(.white.opacity(0.14))
                        .position(x: proxy.size.width / 2, y: proxy.size.height * (cover ? 0.45 : 0.28))
                        .accessibilityHidden(true)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.1), .black.opacity(cover ? 0.28 : 0.65)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
