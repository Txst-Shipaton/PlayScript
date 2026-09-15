import SwiftUI
import StoryCore

struct ReaderView: View {
    @Bindable var model: ReadingModel
    var turnPage: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var narrativeFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedChoice: String?
    @State private var hoveredChoice: String?

    /// A decision is being weighed: the scene, the scrim, and the page chrome all yield.
    private var deciding: Bool { model.needsChoice || model.pendingChoiceID != nil }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LivingScene(mood: model.beat.mood, beatID: model.beat.id,
                            quiet: deciding,
                            resting: model.isPaused || scenePhase != .active,
                            attention: hoveredChoice != nil || focusedChoice != nil || model.pendingChoiceID != nil,
                            activeSpeaker: ["Romeo", "Juliet"].contains(model.voice.activeSpeaker ?? "") ? model.voice.activeSpeaker : model.run.selectedChoice != nil ? "Juliet" : nil,
                            audioLevel: model.voice.activeSpeaker == "Narrator" ? 0 : model.voice.audioLevel,
                            choiceBold: model.run.selectedChoice?.isBold)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: reduceMotion ? 0 : 1.2), value: model.beat.mood)
                LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0),
                                       .init(color: .clear, location: 0.25),
                                       .init(color: .black.opacity(0.7), location: 0.55),
                                       .init(color: .black.opacity(0.94), location: 1)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                // While a decision is open the room draws back another step, so the
                // two thoughts are the only lit things left on the screen.
                LinearGradient(stops: [.init(color: .black.opacity(0.3), location: 0),
                                       .init(color: .black.opacity(0.12), location: 0.3),
                                       .init(color: .black.opacity(0.4), location: 0.62),
                                       .init(color: .black.opacity(0.1), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .opacity(deciding ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .animation(.easeInOut(duration: reduceMotion ? 0 : 0.9), value: deciding)

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
                                if typeSize.isAccessibilitySize {
                                    controls.padding(.top, 22).padding(.bottom, 15)
                                }
                            }
                            .padding(.horizontal, 23)
                            .frame(maxWidth: 570)
                            .frame(minHeight: max(0, geometry.size.height - (typeSize.isAccessibilitySize ? 0 : model.needsChoice ? 225 : 90)))
                            .frame(maxWidth: .infinity)
                        }
                        .scrollIndicators(.hidden)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            if !typeSize.isAccessibilitySize {
                                controls
                                    .padding(.horizontal, 23)
                                    .padding(.top, 14)
                                    .padding(.bottom, 10)
                                    .frame(maxWidth: 570)
                            }
                        }
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
            .simultaneousGesture(DragGesture(minimumDistance: 65).onEnded { value in
                if value.translation.width < -80 && abs(value.translation.height) < 60 { advancePage() }
            })
        }
        .foregroundStyle(Palette.paper)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $model.isPaused, onDismiss: { model.resume() }) { pauseSheet }
        .onChange(of: model.contentID) { _, _ in
            narrativeFocused = true
            focusedChoice = nil
            hoveredChoice = nil
        }
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.5), value: model.contentID)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.3), value: model.pendingChoiceID)
        .sensoryFeedback(.selection, trigger: model.run.selectedChoiceID)
    }

    private var sceneHeading: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(model.run.index + 1) / \(model.story.beats.count)")
                    .font(.caption2.monospacedDigit()).tracking(2)
                    .accessibilityLabel("Page \(model.run.index + 1) of \(model.story.beats.count)")
                Spacer()
                Button { model.pause() } label: {
                    Image(systemName: "pause").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Pause story")
                .accessibilityIdentifier("pauseStory")
            }
            SmallLabel(text: model.beat.chapter)
                .foregroundStyle(.white.opacity(0.8))
            Text(model.beat.title)
                .literary(25, relativeTo: .title2)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(model.beat.location)
                .font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .id(model.beat.id)
        .transition(.opacity)
        .opacity(deciding ? 0.42 : 1)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.9), value: deciding)
    }

    private var narrative: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0xECC4BA)).frame(width: 4, height: 4)
                SmallLabel(text: model.voice.activeSpeaker ?? "Through \(model.beat.pointOfView)’s eyes")
                    .accessibilityIdentifier("activeSpeaker")
                #if DEBUG
                // A stable record of the page's cast for UI tests; a single line can
                // pass by faster than the test harness samples the screen.
                Text(model.voice.speakersHeard.joined(separator: ","))
                    .frame(width: 0, height: 0)
                    .opacity(0.01)
                    .accessibilityIdentifier("speakersHeard")
                #endif
            }
            .foregroundStyle(Color(hex: 0xE9C9C4))
            if let choice = model.run.selectedChoice {
                Label(choice.responseTitle, systemImage: choice.isBold ? "sun.max" : "moon")
                    .font(.subheadline).foregroundStyle(Color(hex: choice.isBold ? 0xFFD6A0 : 0xEABACD))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("choiceConsequence")
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            Text(model.voice.highlightedText(model.text))
                .literary(20)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("narrative")
                .accessibilityFocused($narrativeFocused)
                .id(model.contentID)
                .transition(.opacity)
            if model.voice.available {
                HStack(spacing: 10) {
                    Button { model.voiceEnabled.toggle() } label: {
                        Label(model.voiceEnabled ? "Voice on" : "Listen to this page",
                              systemImage: model.voiceEnabled ? "waveform" : "play.circle")
                            .font(.caption).frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("voiceToggle")
                    if model.voiceEnabled && !reduceMotion {
                        // While the page is read aloud, a pen quietly writes it.
                        LottieLayer(name: "narration-quill",
                                    playing: !model.isPaused && model.pendingChoiceID == nil,
                                    speed: 0.8, fills: false,
                                    colors: ["paper Outlines.**.Stroke 1.Color": .white.opacity(0.55),
                                             "Shape Layer 1.**.Stroke 1.Color": Color(hex: 0xECC4BA),
                                             "Shape Layer 2.**.Stroke 1.Color": Color(hex: 0xECC4BA)])
                            .frame(width: 34, height: 24)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding(.vertical, 24)
    }

    @ViewBuilder private var controls: some View {
        if model.needsChoice {
            VStack(spacing: 12) {
                SmallLabel(text: "Let your heart answer")
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.bottom, 3)
                ForEach(Array(model.beat.choices.enumerated()), id: \.element.id) { index, choice in
                    Button { model.select(choice, reduceMotion: reduceMotion) } label: {
                        HStack(spacing: 10) {
                            Spacer(minLength: 0)
                            Text(choice.title)
                                .literary(17)
                                .multilineTextAlignment(.center)
                            if model.pendingChoiceID == choice.id {
                                if reduceMotion {
                                    Image(systemName: "checkmark").font(.caption)
                                } else {
                                    // The thought is kept: a check draws itself inside
                                    // the half second before the page moves on.
                                    LottieLayer(name: "commit-check", speed: 2.5, loops: false,
                                                colors: ["**.Stroke 1.Color": .white,
                                                         "**.Fill 1.Color": Color(hex: 0xF0DAD8)],
                                                gradients: ["**.Gradient Stroke 1.Colors":
                                                                [Color(hex: 0xF0DAD8), .white]])
                                        .frame(width: 30, height: 30)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                        .frame(minHeight: 56)
                        .background(Color.white.opacity(focusedChoice == choice.id || hoveredChoice == choice.id ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.7))
                    }
                    .buttonStyle(PressStyle())
                    .opacity(model.pendingChoiceID == nil || model.pendingChoiceID == choice.id ? 1 : 0)
                    .offset(y: !reduceMotion && model.pendingChoiceID != nil && model.pendingChoiceID != choice.id ? 24 : 0)
                    .focused($focusedChoice, equals: choice.id)
                    .onHover { hoveredChoice = $0 ? choice.id : nil }
                    .modifier(ThoughtArrival(delay: Double(index) * 0.12, reduceMotion: reduceMotion))
                    .disabled(model.pendingChoiceID != nil)
                    .accessibilityHidden(model.pendingChoiceID != nil && model.pendingChoiceID != choice.id)
                    .accessibilityIdentifier("choice-\(choice.id)")
                }
            }
            .background {
                // A thought arriving, behind the two it could become.
                LottieLayer(name: "accent-thought",
                            playing: !reduceMotion && model.pendingChoiceID == nil,
                            fills: false)
                    .opacity(model.pendingChoiceID == nil ? 0.5 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        } else {
            VStack(spacing: 0) {
                Button { advancePage() } label: {
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
                LottieLayer(name: "accent-letter", playing: !reduceMotion, fills: false)
                    .frame(width: 170, height: 150)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                SmallLabel(text: "A letter. A little more time.")
                Text("What if…")
                    .literary(52, relativeTo: .largeTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(model.voice.highlightedText(model.text))
                    .literary(22)
                    .lineSpacing(8)
                    .accessibilityIdentifier("whatIfText")
                    .accessibilityFocused($narrativeFocused)
                Text("In Shakespeare’s ending, neither lover survives.\nThis is a glimpse of the life they never had.")
                    .font(.footnote)
                    .lineSpacing(5)
                    .foregroundStyle(.white.opacity(0.78))
                Button { advancePage() } label: {
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
                if reduceMotion {
                    Image(systemName: "heart")
                        .font(.system(size: 28, weight: .ultraLight))
                        .padding(.vertical, 12)
                        .accessibilityHidden(true)
                } else {
                    // An unbroken line, drawn and redrawn: what outlasts the story.
                    LottieLayer(name: "ending-infinity", speed: 0.6, fills: false,
                                colors: [
                                    "Path 1a.**.Stroke 1.Color": Color(hex: 0x9D4057),
                                    "Path 1b.**.Stroke 1.Color": Color(hex: 0xF0DAD8),
                                    "Path 1c.**.Stroke 1.Color": Color(hex: 0xECC4BA),
                                    "Path 1d.**.Stroke 1.Color": Color(hex: 0xC97A8A),
                                    "Path 2a.**.Stroke 1.Color": Color(hex: 0x9D4057),
                                    "Path 2b.**.Stroke 1.Color": Color(hex: 0xECC4BA),
                                    "Path 2c.**.Stroke 1.Color": Color(hex: 0xFCF5F0),
                                ])
                        .frame(width: 96, height: 60)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                Text(model.voice.highlightedText(model.text))
                    .literary(29, relativeTo: .title)
                    .lineSpacing(10)
                    .accessibilityIdentifier("reflectionText")
                    .accessibilityFocused($narrativeFocused)
                Rectangle().fill(.white.opacity(0.35)).frame(width: 36, height: 1)
                personalityReflection
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
            if model.voice.available {
                Toggle("Read aloud", isOn: $model.voiceEnabled)
                    .tint(Palette.rose)
            }
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

    private func advancePage() {
        guard model.beat.kind != .reflection else { return }
        if let turnPage { turnPage() } else { model.advance() }
    }

    private var personalityReflection: some View {
        let result = ChoiceReflection(decisions: model.run.decisions)
        return VStack(alignment: .leading, spacing: 18) {
            SmallLabel(text: "Your heart in this story")
            Text(result.character).literary(38, relativeTo: .largeTitle)
                .accessibilityIdentifier("personalityCharacter")
            Text(result.title).literary(22, relativeTo: .title2)
            Text(result.explanation).font(.body).lineSpacing(4)
            ForEach(Array(result.traits.enumerated()), id: \.offset) { index, trait in
                VStack(alignment: .leading, spacing: 5) {
                    Label(trait, systemImage: "sparkle").font(.headline)
                    Text(result.moments[index]).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                }
            }
            Text("A playful reflection of this reading, not a personality test. Different choices reveal different shades of you.")
                .font(.caption).foregroundStyle(.white.opacity(0.65))
        }
        .multilineTextAlignment(.leading)
        .padding(24).glass(dark: true, radius: 24)
    }
}
