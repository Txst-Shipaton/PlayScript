import SwiftUI

struct ThoughtArrival: ViewModifier {
    let delay: Double
    let reduceMotion: Bool
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived || reduceMotion ? 0 : 16)
            .onAppear {
                withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.55).delay(reduceMotion ? 0 : delay)) {
                    arrived = true
                }
            }
    }
}
