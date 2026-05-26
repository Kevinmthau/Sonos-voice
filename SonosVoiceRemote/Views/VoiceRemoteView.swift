import SwiftUI

struct VoiceRemoteView: View {
    @ObservedObject var viewModel: VoiceRemoteViewModel

    @State private var detailsAreExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RemoteBackground()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    roomSelector
                    voiceControl
                    transportControls
                    detailsSection
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private var header: some View {
        GlassPanel(cornerRadius: 30, padding: 16) {
            HStack(alignment: .center, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentBlue.opacity(0.12))
                        Image(systemName: "hifispeaker.2.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.accentBlue)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sonos Voice")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(Color.remoteText)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(connectionTint)
                                .frame(width: 8, height: 8)
                            Text(connectionStatusText)
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color.remoteSecondaryText)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    connectionAction

                    if viewModel.connectionState.status != .authenticationRequired {
                        Button {
                            Task {
                                await viewModel.disconnectSonos()
                            }
                        } label: {
                            Image(systemName: "power")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(GlassIconButtonStyle(tint: .remoteSecondaryText))
                        .accessibilityLabel("Disconnect")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var connectionAction: some View {
        if let authorizationURL = viewModel.authorizationURL,
           viewModel.connectionState.status == .authenticationRequired {
            Link(destination: authorizationURL) {
                Label("Sign In", systemImage: "person.crop.circle.badge.checkmark")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .accessibilityLabel("Sign In")
        } else {
            Button {
                Task {
                    await viewModel.connectSonos()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .accessibilityLabel("Refresh Sonos connection")
        }
    }

    private var roomSelector: some View {
        GlassPanel(cornerRadius: 28, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Selected Room")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.remoteMutedText)
                        Text(viewModel.selectedRoomName)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.remoteText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer(minLength: 8)

                    if viewModel.rooms.count > 1 {
                        Picker("Room", selection: Binding(
                            get: { viewModel.selectedRoomID },
                            set: { viewModel.updateSelectedRoom(id: $0) }
                        )) {
                            ForEach(viewModel.rooms) { room in
                                Text(room.name).tag(room.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.accentBlue)
                    }
                }

                if viewModel.rooms.isEmpty {
                    Text("No Sonos rooms discovered yet.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.remoteSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.rooms) { room in
                                RoomChipButton(
                                    title: room.name,
                                    isSelected: room.id == viewModel.selectedRoomID,
                                    isPlaying: room.isPlaying
                                ) {
                                    viewModel.updateSelectedRoom(id: room.id)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var voiceControl: some View {
        GlassPanel(cornerRadius: 34, padding: 22) {
            VStack(spacing: 18) {
                Button {
                    Task {
                        await viewModel.toggleRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(
                                microphoneTint.opacity(viewModel.isRecording ? 0.28 : 0.16),
                                lineWidth: 18
                            )
                            .frame(width: 178, height: 178)
                            .scaleEffect(viewModel.isRecording && !reduceMotion ? 1.08 : 1.0)
                            .opacity(viewModel.isRecording ? 1 : 0.72)

                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: microphoneGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 138, height: 138)
                            .shadow(color: microphoneTint.opacity(0.24), radius: 28, x: 0, y: 16)

                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .animation(
                        viewModel.isRecording && !reduceMotion
                        ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                        : .easeOut(duration: 0.18),
                        value: viewModel.isRecording
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isMicrophoneToggleDisabled)
                .opacity(viewModel.isMicrophoneToggleDisabled ? 0.55 : 1)
                .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")

                VStack(spacing: 6) {
                    Text(microphoneTitle)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Color.remoteText)

                    Text(viewModel.statusText)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.remoteSecondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var transportControls: some View {
        GlassPanel(cornerRadius: 28, padding: 16) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    TransportButton(title: "Pause", systemImage: "pause.fill") {
                        Task { await viewModel.executeManual(.pause) }
                    }

                    TransportButton(title: "Resume", systemImage: "play.fill", isPrimary: true) {
                        Task { await viewModel.executeManual(.resume) }
                    }

                    TransportButton(title: "Skip", systemImage: "forward.fill") {
                        Task { await viewModel.executeManual(.skip) }
                    }
                }

                HStack(spacing: 10) {
                    SecondaryTransportButton(title: "Volume Down", systemImage: "speaker.wave.1.fill") {
                        Task { await viewModel.executeManual(.volumeDown) }
                    }

                    SecondaryTransportButton(title: "Volume Up", systemImage: "speaker.wave.3.fill") {
                        Task { await viewModel.executeManual(.volumeUp) }
                    }
                }
            }
        }
    }

    private var detailsSection: some View {
        GlassPanel(cornerRadius: 28, padding: 0) {
            DisclosureGroup(isExpanded: $detailsAreExpanded) {
                VStack(alignment: .leading, spacing: 16) {
                    DetailBlock(title: "Live Transcript", systemImage: "text.quote") {
                        Text(viewModel.transcript.isEmpty ? "Your speech will appear here in real time." : viewModel.transcript)
                            .foregroundStyle(viewModel.transcript.isEmpty ? Color.remoteMutedText : Color.remoteText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 56, alignment: .topLeading)
                    }

                    DetailBlock(title: "Parsed Intent", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                        Text(viewModel.parsedIntentSummary)
                            .foregroundStyle(Color.remoteText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    DetailBlock(title: "Execution Status", systemImage: viewModel.isExecuting ? "bolt.fill" : "checkmark.circle.fill") {
                        HStack(alignment: .top, spacing: 10) {
                            Capsule()
                                .fill(viewModel.isExecuting ? Color.accentBlue : Color.remoteGreen)
                                .frame(width: 8, height: 44)
                            Text(viewModel.statusText)
                                .foregroundStyle(Color.remoteText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    DetailBlock(title: "Household", systemImage: "house.fill") {
                        VStack(alignment: .leading, spacing: 10) {
                            if viewModel.households.isEmpty == false {
                                Text(viewModel.selectedHouseholdName)
                                    .font(.system(.headline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Color.remoteText)

                                if viewModel.households.count > 1 {
                                    Picker("Household", selection: Binding(
                                        get: { viewModel.selectedHouseholdID },
                                        set: { newValue in
                                            Task {
                                                await viewModel.updateSelectedHousehold(id: newValue)
                                            }
                                        }
                                    )) {
                                        ForEach(viewModel.households) { household in
                                            Text(household.name).tag(household.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Color.accentBlue)
                                }
                            }

                            Text(viewModel.householdSummaryText)
                                .foregroundStyle(Color.remoteSecondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    DetailBlock(title: "Microphone", systemImage: "waveform") {
                        Text(viewModel.transcriptionSummaryText)
                            .foregroundStyle(Color.remoteSecondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    DetailBlock(title: "Debug Log", systemImage: "terminal.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            if viewModel.debugLog.isEmpty {
                                Text("No activity yet.")
                                    .foregroundStyle(Color.remoteMutedText)
                            } else {
                                ForEach(viewModel.debugLog, id: \.self) { line in
                                    Text(line)
                                        .font(.system(.footnote, design: .monospaced))
                                        .foregroundStyle(Color.remoteSecondaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentBlue)
                    Text("Details")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.remoteText)
                    Spacer()
                    Text(detailsAreExpanded ? "Hide" : "Show")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.remoteMutedText)
                }
                .padding(18)
            }
            .accentColor(Color.accentBlue)
        }
    }

    private var microphoneTitle: String {
        if viewModel.isTranscribing {
            return "Transcribing..."
        }

        return viewModel.isRecording ? "Listening live..." : "Ready for a command"
    }

    private var microphoneTint: Color {
        viewModel.isRecording ? .remoteRed : .accentBlue
    }

    private var microphoneGradient: [Color] {
        if viewModel.isRecording {
            return [.remoteRed, Color(red: 0.98, green: 0.45, blue: 0.39)]
        }

        return [.accentBlue, Color(red: 0.36, green: 0.63, blue: 1.0)]
    }

    private var connectionTint: Color {
        switch viewModel.connectionState.status {
        case .ready:
            return .remoteGreen
        case .authenticationRequired, .configurationRequired:
            return .remoteAmber
        case .unavailable:
            return .remoteRed
        }
    }

    private var connectionStatusText: String {
        switch viewModel.connectionState.status {
        case .ready:
            return "Connected"
        case .authenticationRequired:
            return "Sign in required"
        case .configurationRequired:
            return "Setup needed"
        case .unavailable:
            return "Unavailable"
        }
    }
}

private struct RemoteBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.99, blue: 1.0),
                Color(red: 0.93, green: 0.96, blue: 0.99),
                Color(red: 0.88, green: 0.93, blue: 0.97)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct GlassPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 28, padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.38))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.74), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.07), radius: 22, x: 0, y: 14)
    }
}

private struct RoomChipButton: View {
    let title: String
    let isSelected: Bool
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isPlaying ? Color.remoteGreen : Color.remoteMutedText.opacity(0.55))
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? .white : Color.remoteText)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentBlue : Color.white.opacity(0.58))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isSelected ? Color.clear : Color.remoteHairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select \(title)")
    }
}

private struct TransportButton: View {
    let title: String
    let systemImage: String
    var isPrimary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: isPrimary ? 22 : 19, weight: .bold))
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
        }
        .buttonStyle(TransportButtonStyle(isPrimary: isPrimary))
        .accessibilityLabel(title)
    }
}

private struct SecondaryTransportButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(SecondaryTransportButtonStyle())
        .accessibilityLabel(title)
    }
}

private struct DetailBlock<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Color.remoteMutedText)
                .labelStyle(.titleAndIcon)
            content
                .font(.system(.footnote, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.remoteHairline, lineWidth: 1)
                )
        )
    }
}

private struct PrimaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentBlue.opacity(configuration.isPressed ? 0.78 : 1))
            )
            .shadow(color: Color.accentBlue.opacity(0.22), radius: 12, x: 0, y: 7)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct GlassIconButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.52 : 0.7))
                    .overlay(
                        Circle()
                            .stroke(Color.remoteHairline, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct TransportButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isPrimary ? .white : Color.remoteText)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isPrimary ? Color.accentBlue : Color.white.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(isPrimary ? Color.clear : Color.remoteHairline, lineWidth: 1)
                    )
            )
            .shadow(color: isPrimary ? Color.accentBlue.opacity(0.2) : Color.clear, radius: 14, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct SecondaryTransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.remoteText)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.46 : 0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.remoteHairline, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private extension Color {
    static let remoteText = Color(red: 0.08, green: 0.12, blue: 0.18)
    static let remoteSecondaryText = Color(red: 0.31, green: 0.38, blue: 0.48)
    static let remoteMutedText = Color(red: 0.48, green: 0.55, blue: 0.64)
    static let remoteHairline = Color.black.opacity(0.08)
    static let accentBlue = Color(red: 0.08, green: 0.37, blue: 0.86)
    static let remoteGreen = Color(red: 0.12, green: 0.58, blue: 0.35)
    static let remoteRed = Color(red: 0.84, green: 0.22, blue: 0.22)
    static let remoteAmber = Color(red: 0.86, green: 0.52, blue: 0.12)
}
