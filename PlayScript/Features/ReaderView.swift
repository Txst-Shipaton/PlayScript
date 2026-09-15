import SwiftUI
import StoryCore

struct ReaderView: View {
    @Bindable var model: ReadingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var narrativeFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SceneBackdrop(
                    mood: model.beat.mood,
                    artwork: model.beat.artwork,
                    animationName: SceneAnimation.name(for: model.beat.id)
                )
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: reduceMotion ? 0 : 1.2), value: model.beat.mood)

                if model.beat.kind == .reflection {
                    reflection
                } else if model.beat.kind == .whatIf {
                    whatIf
                } else {
                    ScrollViewReader { scroll in
                        ScrollView {
                            VStack(spacing: 0) {
                                Color.clear.frame(height: 1).id("top")
                                sceneHeading
                                    .padding(.top, 27)
                                Spacer(minLength: max(40, geometry.size.height * 0.12))
                                narrative
                                controls
                                    .padding(.top, 22)
                                    .padding(.bottom, 15)
                            }
                            .padding(.horizontal, 23)
                            .frame(maxWidth: 570)
                            .frame(minHeight: geometry.size.height)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: model.contentID) { _, _ in
                            scroll.scrollTo("top", anchor: .top)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.6)
                    .onEnded { _ in model.pause() }
            )
            .accessibilityAction(named: "Pause story") { model.pause() }
            .accessibilityAction(.escape) { model.pause() }
        }
        .foregroundStyle(Palette.paper)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $model.isPaused, onDismiss: { model.resume() }) { pauseSheet }
        .onChange(of: model.contentID) { _, _ in narrativeFocused = true }
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.5), value: model.contentID)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.3), value: model.pendingChoiceID)
    }

    private var sceneHeading: some View {
        VStack(spacing: 12) {
            SmallLabel(text: model.beat.chapter)
                .foregroundStyle(.white.opacity(0.8))
            Text(model.beat.title)
                .literary(25, relativeTo: .title2)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }
        .id(model.beat.id)
        .transition(.opacity)
    }

    private var narrative: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0xECC4BA)).frame(width: 4, height: 4)
                SmallLabel(text: "As \(model.beat.pointOfView)")
            }
            .foregroundStyle(Color(hex: 0xE9C9C4))
            Text(model.text)
                .literary(20)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("narrative")
                .accessibilityFocused($narrativeFocused)
                .id(model.contentID)
                .transition(.opacity)
        }
        .padding(24)
        .glass(dark: true, radius: 29)
    }

    @ViewBuilder private var controls: some View {
        if model.needsChoice {
            VStack(spacing: 12) {
                SmallLabel(text: "Let your heart answer")
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.bottom, 3)
                ForEach(model.beat.choices) { choice in
                    Button { model.select(choice, reduceMotion: reduceMotion) } label: {
                        HStack(spacing: 10) {
                            Spacer(minLength: 0)
                            Text(choice.title)
                                .literary(17)
                                .multilineTextAlignment(.center)
                            if model.pendingChoiceID == choice.id {
                                Image(systemName: "checkmark").font(.caption)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                        .frame(minHeight: 56)
                        .glass(dark: true, radius: 32)
                    }
                    .buttonStyle(PressStyle())
                    .opacity(model.pendingChoiceID == nil || model.pendingChoiceID == choice.id ? 1 : 0)
                    .disabled(model.pendingChoiceID != nil)
                    .accessibilityHidden(model.pendingChoiceID != nil && model.pendingChoiceID != choice.id)
                    .accessibilityIdentifier("choice-\(choice.id)")
                }
            }
        } else {
            VStack(spacing: 0) {
                Button { model.advance() } label: {
                    HStack(spacing: 12) {
                        Text("Tap to continue").font(.system(.subheadline, design: .serif))
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .light))
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("continueStory")
                Text("Touch & hold to pause")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.68))
                    .accessibilityHidden(true)
            }
        }
    }

    private var whatIf: some View {
        ScrollView {
            VStack(spacing: 30) {
                Spacer(minLength: 80)
                Image(systemName: "envelope.open")
                    .font(.system(size: 29, weight: .ultraLight))
                    .foregroundStyle(Color(hex: 0xE9C9C4))
                    .accessibilityHidden(true)
                SmallLabel(text: "A letter. A little more time.")
                Text("What if…")
                    .literary(52, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(model.text)
                    .literary(22)
                    .lineSpacing(8)
                    .accessibilityIdentifier("whatIfText")
                    .accessibilityFocused($narrativeFocused)
                Text("In Shakespeare’s ending, neither lover survives.\nThis is a glimpse of the life they never had.")
                    .font(.footnote)
                    .lineSpacing(5)
                    .foregroundStyle(.white.opacity(0.78))
                Button { model.advance() } label: {
                    Text("Imagine it with me")
                        .literary(18)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 20)
                        .glass(dark: true, radius: 32)
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("enterWhatIf")
                Text("A moment through Romeo’s eyes")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 60)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 36)
            .frame(maxWidth: 530)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .transition(.opacity)
    }

    private var reflection: some View {
        ScrollView {
            VStack(spacing: 30) {
                Spacer(minLength: 100)
                SmallLabel(text: "The end · Romeo & Juliet")
                Image(systemName: "heart")
                    .font(.system(size: 28, weight: .ultraLight))
                    .padding(.vertical, 12)
                    .accessibilityHidden(true)
                Text(model.text)
                    .literary(29, relativeTo: .title)
                    .lineSpacing(10)
                    .accessibilityIdentifier("reflectionText")
                    .accessibilityFocused($narrativeFocused)
                Rectangle().fill(.white.opacity(0.35)).frame(width: 36, height: 1)
                Text("PlayScript")
                    .literary(37, relativeTo: .largeTitle)
                    .tracking(-1.5)
                Text("Keep a little of this story with you.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                Button { model.returnToLibrary() } label: {
                    Text("Close the book")
                        .literary(17)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 32)
                        .glass(dark: true, radius: 30)
                }
                .padding(.top, 15)
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("closeBook")
                Spacer(minLength: 60)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .frame(maxWidth: 530)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .transition(.opacity)
    }

    private var pauseSheet: some View {
        ScrollView {
        VStack(spacing: 23) {
            SmallLabel(text: "A breath between the pages")
                .foregroundStyle(Palette.muted)
            Text("Your story will wait.")
                .literary(29, relativeTo: .title)
            Text("Your place is saved.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
            Toggle("Original soundscape", isOn: $model.soundEnabled)
                .tint(Palette.rose)
                .padding(18)
                .glass(radius: 20)
            Button { model.resume() } label: {
                Text("Back to the moment")
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Palette.rose, in: Capsule())
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("resumeStory")
            Button("Return to the library") { model.returnToLibrary() }
                .frame(minHeight: 44)
                .accessibilityIdentifier("returnToLibrary")
        }
        .buttonStyle(PressStyle())
        .padding(30)
        .foregroundStyle(Palette.ink)
        }
        .frame(maxHeight: .infinity)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.paper)
    }
}
