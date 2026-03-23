import SwiftUI

struct VoiceRemoteView: View {
    @ObservedObject var viewModel: VoiceRemoteViewModel

    private let actionColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.16),
                    Color(red: 0.17, green: 0.10, blue: 0.10),
                    Color(red: 0.34, green: 0.19, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    controllerCard
                    roomsCard
                    microphoneCard
                    transcriptCard
                    parsedIntentCard
                    statusCard
                    manualControlsCard
                    debugLogCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SonosVoiceRemote")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text("Tap once to talk. Tap again to send the command to Sonos.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
        }
    }

    private var controllerCard: some View {
        card(title: "Sonos Controller") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Real Sonos Controller")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)

                        Text(viewModel.connectionState.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.orange.opacity(0.85))
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if let authorizationURL = viewModel.authorizationURL,
                           viewModel.connectionState.status == .authenticationRequired {
                            Link(destination: authorizationURL) {
                                Text("Sign In")
                                    .frame(minWidth: 72)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        } else {
                            Button("Refresh") {
                                Task {
                                    await viewModel.connectSonos()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }

                        Button("Disconnect") {
                            Task {
                                await viewModel.disconnectSonos()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }

                Text(viewModel.connectionState.detail)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.86))

                if viewModel.households.isEmpty == false {
                    Text("Selected household")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.orange.opacity(0.85))

                    Text(viewModel.selectedHouseholdName)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)

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
                        .tint(.white)
                    }
                }

                Text(viewModel.householdSummaryText)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var roomsCard: some View {
        card(title: "Rooms") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Selected room")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.orange.opacity(0.85))
                    Spacer()
                    Button("Refresh") {
                        Task {
                            await viewModel.refreshRooms()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                Text(viewModel.selectedRoomName)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)

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
                    .tint(.white)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.rooms) { room in
                            RoomChip(
                                title: room.name,
                                isSelected: room.id == viewModel.selectedRoomID,
                                isPlaying: room.isPlaying
                            )
                        }
                    }
                }

                Text(viewModel.roomSummaryText)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
    }

    private var microphoneCard: some View {
        card(title: "Tap To Talk") {
            VStack(spacing: 18) {
                Button {
                    Task {
                        await viewModel.toggleRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.orange)
                            .frame(width: 142, height: 142)
                            .shadow(color: (viewModel.isRecording ? Color.red : Color.orange).opacity(0.45), radius: 28)

                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 3)
                            .frame(width: 164, height: 164)

                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")

                Text(viewModel.isRecording ? "Listening live..." : "Ready for a command")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)

                Text(viewModel.permissionState.statusMessage)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var transcriptCard: some View {
        card(title: "Live Transcript") {
            Text(viewModel.transcript.isEmpty ? "Your speech will appear here in real time." : viewModel.transcript)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(viewModel.transcript.isEmpty ? Color.white.opacity(0.55) : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 72, alignment: .topLeading)
        }
    }

    private var parsedIntentCard: some View {
        card(title: "Parsed Intent") {
            Text(viewModel.parsedIntentSummary)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusCard: some View {
        card(title: "Execution Status") {
            HStack(alignment: .top, spacing: 12) {
                Capsule()
                    .fill(viewModel.isExecuting ? Color.orange : Color.green)
                    .frame(width: 10, height: 52)

                Text(viewModel.statusText)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var manualControlsCard: some View {
        card(title: "Manual Controls") {
            LazyVGrid(columns: actionColumns, spacing: 10) {
                ManualActionButton(title: "Pause", systemImage: "pause.fill", tint: .orange) {
                    Task { await viewModel.executeManual(.pause) }
                }
                ManualActionButton(title: "Resume", systemImage: "play.fill", tint: .green) {
                    Task { await viewModel.executeManual(.resume) }
                }
                ManualActionButton(title: "Skip", systemImage: "forward.fill", tint: .blue) {
                    Task { await viewModel.executeManual(.skip) }
                }
                ManualActionButton(title: "Volume Up", systemImage: "speaker.wave.3.fill", tint: .pink) {
                    Task { await viewModel.executeManual(.volumeUp) }
                }
                ManualActionButton(title: "Volume Down", systemImage: "speaker.wave.1.fill", tint: .purple) {
                    Task { await viewModel.executeManual(.volumeDown) }
                }
            }
        }
    }

    private var debugLogCard: some View {
        card(title: "Debug Log") {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.debugLog.isEmpty {
                    Text("No activity yet.")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.6))
                } else {
                    ForEach(viewModel.debugLog, id: \.self) { line in
                        Text(line)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Color.white.opacity(0.72))
                .tracking(1.2)
            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct RoomChip: View {
    let title: String
    let isSelected: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isPlaying ? Color.green : Color.gray.opacity(0.7))
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(isSelected ? Color.orange.opacity(0.85) : Color.white.opacity(0.08))
        )
        .foregroundStyle(.white)
    }
}

private struct ManualActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(.body, design: .rounded).weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }
}
