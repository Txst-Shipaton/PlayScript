import Lottie
import SwiftUI

/// A bundled Lottie animation, hosted in a plain container so the animation's own
/// intrinsic size never drives SwiftUI layout.
///
/// A `<name>.lottie` archive in the bundle wins over `<name>.json`. dotLottie
/// files unpack off the main thread, so they appear a moment after the view; JSON
/// animations load synchronously exactly as before.
///
/// The animations are decorative. A missing or unreadable file simply plays
/// nothing: `LivingScene` keeps its native atmosphere layer either way, so no
/// scene depends on Lottie to stay in motion.
struct LottieLayer: UIViewRepresentable {
    let name: String
    var playing = true
    var speed: Double = 1
    var fills = true
    /// When false the animation plays through once per load and then holds.
    var loops = true
    /// The frame shown while the animation is not playing, from 0 to 1. Lets a
    /// play-once animation rest on its finished state under Reduce Motion.
    var stillProgress: Double = 0
    /// Runtime recolouring, keyed by `AnimationKeypath` string, e.g. `"**.Stroke 1.Color"`.
    var colors: [String: Color] = [:]
    /// Gradient recolouring, keyed by keypath string, e.g. `"**.Gradient Stroke 1.Colors"`.
    var gradients: [String: [Color]] = [:]

    final class Coordinator {
        var animationView: LottieAnimationView?
        var loadedName: String?
        var latest: LottieLayer?
        var hasPlayed = false
        var appliedColors: [String: Color]?
        var appliedGradients: [String: [Color]]?

        /// Pushes the current SwiftUI state onto the view. Runs after every
        /// update, and again once an asynchronously loaded dotLottie arrives,
        /// because loading a dotLottie resets loop mode and speed from its manifest.
        func apply() {
            guard let layer = latest, let animationView else { return }
            animationView.contentMode = layer.fills ? .scaleAspectFill : .scaleAspectFit
            animationView.animationSpeed = layer.speed
            animationView.loopMode = layer.loops ? .loop : .playOnce
            guard animationView.animation != nil else { return }

            if appliedColors != layer.colors {
                appliedColors = layer.colors
                for (keypath, color) in layer.colors {
                    animationView.setValueProvider(ColorValueProvider(UIColor(color).lottieColor),
                                                   keypath: AnimationKeypath(keypath: keypath))
                }
            }
            if appliedGradients != layer.gradients {
                appliedGradients = layer.gradients
                for (keypath, stops) in layer.gradients {
                    animationView.setValueProvider(GradientValueProvider(stops.map { UIColor($0).lottieColor }),
                                                   keypath: AnimationKeypath(keypath: keypath))
                }
            }

            if layer.playing {
                if layer.loops {
                    if !animationView.isAnimationPlaying { animationView.play() }
                } else if !hasPlayed {
                    hasPlayed = true
                    animationView.play()
                }
            } else {
                if animationView.isAnimationPlaying { animationView.pause() }
                if !hasPlayed { animationView.currentProgress = layer.stillProgress }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true

        let animationView = LottieAnimationView()
        animationView.loopMode = .loop
        animationView.contentMode = fills ? .scaleAspectFill : .scaleAspectFit
        // Playback state survives a trip through the background without a restart.
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            animationView.topAnchor.constraint(equalTo: container.topAnchor),
            animationView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.animationView = animationView
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.latest = self
        guard let animationView = coordinator.animationView else { return }
        if coordinator.loadedName != name {
            coordinator.loadedName = name
            coordinator.hasPlayed = false
            coordinator.appliedColors = nil
            coordinator.appliedGradients = nil
            if Bundle.main.url(forResource: name, withExtension: "lottie") != nil {
                animationView.animation = nil
                let requested = name
                // Unzips on a background queue (and caches), then calls back on main.
                DotLottieFile.named(requested) { [weak coordinator] result in
                    guard let coordinator, coordinator.loadedName == requested,
                          let view = coordinator.animationView,
                          case .success(let file) = result else { return }
                    view.loadAnimation(from: file)
                    view.currentProgress = 0
                    coordinator.apply()
                }
            } else {
                animationView.animation = LottieAnimation.named(name)
                animationView.currentProgress = 0
            }
        }
        coordinator.apply()
    }

    static func dismantleUIView(_ container: UIView, coordinator: Coordinator) {
        coordinator.loadedName = nil
        coordinator.animationView?.stop()
    }
}

private extension UIColor {
    var lottieColor: LottieColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return LottieColor(r: Double(red), g: Double(green), b: Double(blue), a: Double(alpha))
    }
}
