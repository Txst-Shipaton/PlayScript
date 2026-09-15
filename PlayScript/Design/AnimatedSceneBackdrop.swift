import SwiftUI
import Lottie

enum SceneAnimation {
    static func name(for beatID: String) -> String? {
        switch beatID {
        case "window": "opening"
        case "window-choice": "balcony_choice"
        case "names", "vow": "confession"
        case "vow-choice", "morning": "vow_choice"
        case "friar", "plan": "the_letter"
        case "potion-choice", "sleep": "vial_choice"
        case "wake", "letter-lost", "last-kiss": "the_tomb"
        case "what-if": "whatif_prompt"
        case "road", "ride", "in-time", "enough-time": "whatif"
        case "reflection": "closing"
        default: nil
        }
    }
}

struct AnimatedSceneBackdrop: UIViewRepresentable {
    let name: String
    let reduceMotion: Bool

    final class Coordinator {
        var loadedName: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundBehavior = .pauseAndRestore
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: LottieAnimationView, context: Context) {
        configure(view, coordinator: context.coordinator)
    }

    private func configure(_ view: LottieAnimationView, coordinator: Coordinator) {
        if coordinator.loadedName != name {
            guard let animation = LottieAnimation.named(name, bundle: .main) else {
                assertionFailure("Missing or invalid Lottie animation: \(name).json")
                return
            }
            view.animation = animation
            coordinator.loadedName = name
        }
        if reduceMotion {
            view.pause()
            view.currentProgress = 0.5
        } else if !view.isAnimationPlaying {
            view.loopMode = .loop
            view.play()
        }
    }
}
