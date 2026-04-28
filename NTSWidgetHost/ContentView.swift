import SwiftUI

struct ContentView: View {
    @ObservedObject var playerService: RadioPlayerService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("NTS")
                    .font(.headline)

                Spacer()

                Text(playerService.state.currentStation?.displayName ?? "Idle")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.quaternary))
            }

            Text(statusOrErrorLine)
                .font(.title3)
                .foregroundStyle(hasError ? .red : .primary)
                .lineLimit(1)

            HStack(spacing: 12) {
                Button("1") {
                    runPlay(.nts1)
                }
                .keyboardShortcut("1")

                Button("2") {
                    runPlay(.nts2)
                }
                .keyboardShortcut("2")

                Button {
                    runToggle()
                } label: {
                    Image(systemName: playerService.state.isPlaying ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 180)
    }

    private func runPlay(_ station: Station) {
        Task {
            _ = try? await playerService.play(station: station)
        }
    }

    private func runToggle() {
        Task {
            _ = try? await playerService.togglePlayback()
        }
    }

    private var hasError: Bool {
        !(playerService.state.lastError?.isEmpty ?? true)
    }

    private var statusOrErrorLine: String {
        if let error = playerService.state.lastError, !error.isEmpty {
            return error
        }

        return playerService.state.statusText
    }
}
