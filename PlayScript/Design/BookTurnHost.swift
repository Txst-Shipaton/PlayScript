import SwiftUI
import UIKit

/// UIKit curls a snapshot of the outgoing page over the newly rendered scene.
/// The snapshot has no live audio or controls; only the current reader is interactive.
struct BookTurnHost: UIViewControllerRepresentable {
    let model: ReadingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor final class Coordinator {
        weak var host: UIHostingController<ReaderView>?
        var turning = false

        func turn(_ model: ReadingModel, reduced: Bool) {
            guard !turning, !model.needsChoice, !model.isPaused,
                  model.pendingChoiceID == nil else { return }
            guard !reduced, let host, let snapshot = host.view.snapshotView(afterScreenUpdates: false) else {
                model.advance()
                return
            }
            let index = model.run.index
            model.setPageTurning(true)
            model.advance()
            guard model.run.index != index else { model.setPageTurning(false); return }
            turning = true
            host.view.isUserInteractionEnabled = false
            let overlay = UIView(frame: host.view.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            snapshot.frame = overlay.bounds
            overlay.addSubview(snapshot)
            host.view.addSubview(overlay)
            let revealed = UIView(frame: overlay.bounds)
            revealed.backgroundColor = .clear
            // Allow SwiftUI to lay out the incoming page underneath the snapshot.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                UIView.transition(from: snapshot, to: revealed, duration: 0.8,
                                  options: [.transitionCurlUp, .curveEaseInOut]) { _ in
                    overlay.removeFromSuperview()
                    host.view.isUserInteractionEnabled = true
                    self.turning = false
                    model.setPageTurning(false)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> UIHostingController<ReaderView> {
        let coordinator = context.coordinator
        let host = UIHostingController(rootView: ReaderView(model: model, turnPage: {
            coordinator.turn(model, reduced: reduceMotion)
        }))
        host.view.backgroundColor = UIColor(Palette.ink)
        coordinator.host = host
        return host
    }
    func updateUIViewController(_ host: UIHostingController<ReaderView>, context: Context) {
        let coordinator = context.coordinator
        host.rootView = ReaderView(model: model, turnPage: { coordinator.turn(model, reduced: reduceMotion) })
    }
}
