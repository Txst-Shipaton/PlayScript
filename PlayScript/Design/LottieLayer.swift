import Lottie
import SwiftUI

/// A bundled Lottie animation, hosted in a plain container so the animation's own
/// intrinsic size never drives SwiftUI layout.
///
/// The animations are decorative. A missing or unreadable file simply plays
/// nothing: `LivingScene` keeps its native atmosphere layer either way, so no
/// scene depends on Lottie to stay in motion.
struct LottieLayer: UIViewRepresentable {
    let name: String
    var playing = true
    var speed: Double = 1
    var fills = true

    final class Coordinator {
        var animationView: LottieAnimationView?
        var loadedName: String?
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
        guard let animationView = context.coordinator.animationView else { return }
        if context.coordinator.loadedName != name {
            context.coordinator.loadedName = name
            animationView.animation = LottieAnimation.named(name)
            animationView.currentProgress = 0
        }
        animationView.contentMode = fills ? .scaleAspectFill : .scaleAspectFit
        animationView.animationSpeed = speed
        guard animationView.animation != nil else { return }
        if playing {
            if !animationView.isAnimationPlaying { animationView.play() }
        } else if animationView.isAnimationPlaying {
            animationView.pause()
        }
    }

    static func dismantleUIView(_ container: UIView, coordinator: Coordinator) {
        coordinator.animationView?.stop()
    }
}
