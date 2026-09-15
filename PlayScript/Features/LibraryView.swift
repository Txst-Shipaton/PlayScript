import SwiftUI

struct LibraryView: View {
    @Bindable var model: ReadingModel
    @State private var showRestart = false
    @State private var showAbout = false
    @State private var restartTaps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 27) {
                    header
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PlayScript")
                            .literary(47, relativeTo: .largeTitle)
                            .tracking(-2)
                            .accessibilityAddTraits(.isHeader)
                        Text("Some love stories\nare meant to be lived.")
                            .literary(20, relativeTo: .title3)
                            .foregroundStyle(Palette.muted)
                            .lineSpacing(4)
                    }

                    storyCard(height: min(350, max(270, geometry.size.height * 0.41)))

                    HStack(alignment: .top, spacing: 15) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 21, weight: .light))
                            .padding(13)
                            .glass(radius: 17)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("More hearts to get lost in")
                                .literary(17)
                            Text("New stories are on their way.")
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                        }
                        .padding(.top, 5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 27)
                .padding(.top, 15)
                .padding(.bottom, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 11) {
                Button { model.start() } label: {
                    HStack {
                        Spacer()
                        Text(model.canResume ? "Return to your story" : model.hasFinished ? "Live the story again" : "Become Juliet")
                            .font(.system(.body, design: .serif, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 16, weight: .light))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 23)
                    .padding(.vertical, 19)
                    .foregroundStyle(.white)
                    .background(Palette.rose, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("beginStory")

                if model.canResume {
                    Button {
                        restartTaps += 1
                        withAnimation(RestartPrompt.presentAnimation(reduceMotion)) { showRestart = true }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .medium))
                                .symbolEffect(.rotate, value: reduceMotion ? 0 : restartTaps)
                                .accessibilityHidden(true)
                            Text("Begin again")
                                .font(.system(.subheadline, design: .serif, weight: .medium))
                        }
                        .foregroundStyle(Palette.rose)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .glass(radius: 22)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityHint("Asks before starting the story over from the first page.")
                    .accessibilityIdentifier("beginAgain")
                } else {
                    Text("A little time. A whole other life.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, 27)
            .padding(.top, 17)
            .padding(.bottom, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Palette.paper.opacity(0.97))
        }
        .accessibilityHidden(showRestart)
        .overlay {
            RestartPrompt(isPresented: $showRestart) { model.start(over: true) }
        }
        .sheet(isPresented: $showAbout) { about }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                Image(systemName: "heart").font(.system(size: 12, weight: .light))
                SmallLabel(text: "A life between the lines")
            }
            Spacer(minLength: 4)
            Button { model.soundEnabled.toggle() } label: {
                Image(systemName: model.soundEnabled ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: 17, weight: .light))
                    .frame(width: 44, height: 44)
                    .glass(radius: 22)
            }
            .accessibilityLabel(model.soundEnabled ? "Sound on" : "Sound off")
            .accessibilityHint("Double tap to toggle the original soundscape.")
            .accessibilityIdentifier("soundToggle")
        }
        .foregroundStyle(Palette.rose)
    }

    private func storyCard(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            ZStack(alignment: .bottomLeading) {
                SceneBackdrop(mood: .longing, cover: true)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SmallLabel(text: "The first story")
                        Spacer()
                        Image(systemName: "sparkle").font(.system(size: 16, weight: .ultraLight))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 30)
                    SmallLabel(text: "Verona, Italy")
                        .foregroundStyle(Color(hex: 0xE7C5C5))
                    Text("Romeo\n& Juliet")
                        .literary(43, relativeTo: .largeTitle)
                        .lineSpacing(-3)
                        .tracking(-1.5)
                        .foregroundStyle(Palette.paper)
                        .accessibilityLabel("Romeo and Juliet")
                    Text(model.story.author)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(25)
            }
            .frame(minHeight: height)
            .clipShape(.rect(cornerRadius: 30))
            .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white.opacity(0.6), lineWidth: 1))
            .shadow(color: Palette.rose.opacity(0.12), radius: 18, x: 0, y: 9)
            .accessibilityElement(children: .combine)

            HStack(alignment: .center) {
                Text("Her heart. Your voice.")
                    .literary(16)
                Spacer()
                Button { showAbout = true } label: {
                    HStack(spacing: 6) {
                        Text("8–10 min").font(.caption)
                        Image(systemName: "info.circle").font(.system(size: 14))
                    }
                    .frame(minHeight: 44)
                }
                .foregroundStyle(Palette.muted)
                .accessibilityLabel("About this eight to ten minute story")
            }
        }
    }

    private var about: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("A familiar story.\nAn intimate telling.")
                        .literary(29, relativeTo: .title)
                    Text("Live these moments as Juliet. Your choices shape how she expresses herself, while the events stay faithful to Shakespeare’s story.")
                    Text("Near the end, a clearly marked imagined scene lets you glimpse a different possibility through Romeo’s eyes.")
                    Text("Original prose and an original ambient score, kept entirely on your device. No accounts, no connection needed.")
                    Text("During the story, touch and hold anywhere to pause. Your place is saved automatically.")
                        .foregroundStyle(Palette.rose)
                }
                .font(.body)
                .lineSpacing(5)
                .padding(27)
            }
            .background(Palette.paper)
            .foregroundStyle(Palette.ink)
            .navigationTitle("About this telling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAbout = false } } }
        }
        .tint(Palette.rose)
    }
}
