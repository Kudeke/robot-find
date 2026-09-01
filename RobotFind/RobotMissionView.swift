import SwiftUI

@MainActor
final class RobotMissionViewModel: ObservableObject {
    @Published private(set) var currentMission: Mission?
    @Published private(set) var isStarting = false
    @Published var errorMessage: String?
    private var pollingTask: Task<Void, Never>?

    deinit {
        pollingTask?.cancel()
    }

    func createAndStart(item: FMTItem, connectionManager: SSHConnectionManager) async {
        guard let objectID = item.objectProfile?.objectID, !objectID.isEmpty else {
            errorMessage = "Teach this item before searching."
            return
        }
        guard connectionManager.state == .connected,
              let baseURL = connectionManager.localBaseURL else {
            errorMessage = "Connect to the server before starting a search."
            return
        }

        isStarting = true
        errorMessage = nil
        print("[Mission] find tapped localItem=\(item.id)")
        print("[Mission] object_id=\(objectID)")

        do {
            let api = ServerAPI(baseURL: baseURL)
            let created = try await api.createMission(objectID: objectID)
            currentMission = created
            print("[Mission] created mission_id=\(created.missionID) state=\(created.state.rawValue)")

            let started = try await api.startMission(missionID: created.missionID)
            currentMission = started
            print("[Mission] started state=\(started.state.rawValue)")
            startPolling(connectionManager: connectionManager)
        } catch {
            errorMessage = error.localizedDescription
            print("[Mission] failed: \(String(reflecting: error))")
        }
        isStarting = false
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func startPolling(connectionManager: SSHConnectionManager) {
        guard pollingTask == nil,
              let missionID = currentMission?.missionID,
              currentMission?.state.isTerminal == false else { return }

        pollingTask = Task { @MainActor [weak self, weak connectionManager] in
            var consecutiveFailures = 0
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let self,
                          let connectionManager,
                          let baseURL = connectionManager.localBaseURL else {
                        consecutiveFailures += 1
                        if consecutiveFailures >= 3 {
                            self?.errorMessage = "Connection lost. Reconnect to the server."
                        }
                        continue
                    }

                    let mission = try await ServerAPI(baseURL: baseURL).getMission(missionID: missionID)
                    consecutiveFailures = 0
                    if self.errorMessage == "Connection lost. Reconnect to the server." {
                        self.errorMessage = nil
                    }
                    self.currentMission = mission
                    print("[Mission] poll mission_id=\(missionID) state=\(mission.state.rawValue)")

                    if mission.state.isTerminal {
                        print("[Mission] polling stopped terminal=\(mission.state.rawValue)")
                        self.stopPolling()
                    }
                } catch is CancellationError {
                    break
                } catch {
                    consecutiveFailures += 1
                    print("[Mission] poll failed (attempt \(consecutiveFailures)): \(error.localizedDescription)")
                    if consecutiveFailures >= 3 {
                        self?.errorMessage = "Could not refresh robot search status. Check the server connection."
                    }
                }
            }
        }
    }
}

struct RobotMissionView: View {
    let item: FMTItem

    @EnvironmentObject private var connectionManager: SSHConnectionManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = RobotMissionViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: missionIcon)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(missionColor)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Finding \(item.name)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(FMTTheme.text)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    if viewModel.isStarting {
                        ProgressView()
                        Text("Starting robot search...")
                            .foregroundStyle(FMTTheme.textSecondary)
                    } else if let mission = viewModel.currentMission {
                        Text(missionStateText(mission.state))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(mission.state == .failed ? FMTTheme.error : FMTTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Preparing robot search...")
                            .foregroundStyle(FMTTheme.textSecondary)
                    }
                }

                if let mission = viewModel.currentMission {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Mission ID")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FMTTheme.textSecondary)
                        Text(mission.missionID)
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundStyle(FMTTheme.text)
                            .textSelection(.enabled)
                        Text("State: \(mission.state.rawValue)")
                            .foregroundStyle(FMTTheme.textSecondary)
                        if !mission.navigationInstruction.isEmpty {
                            Text("Navigation instruction")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(FMTTheme.textSecondary)
                            Text(mission.navigationInstruction)
                                .foregroundStyle(FMTTheme.text)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(FMTTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.card))
                    .padding(.horizontal, 20)
                    .accessibilityElement(children: .combine)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(FMTTheme.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .accessibilityLabel(errorMessage)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(FMTTheme.background)
            .navigationTitle("Robot Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await viewModel.createAndStart(item: item, connectionManager: connectionManager)
            }
            .onDisappear {
                viewModel.stopPolling()
            }
        }
    }

    private func missionStateText(_ state: MissionState) -> String {
        switch state {
        case .ready, .starting, .running, .verifying, .resuming: return "Searching..."
        case .stopping, .stopped: return "Stopped"
        case .failed: return "Search failed"
        case .targetFound: return "Found"
        }
    }

    private var missionIcon: String {
        switch viewModel.currentMission?.state {
        case .targetFound:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle"
        default:
            return "figure.walk"
        }
    }

    private var missionColor: Color {
        switch viewModel.currentMission?.state {
        case .targetFound:
            return FMTTheme.success
        case .failed:
            return FMTTheme.error
        default:
            return FMTTheme.accent
        }
    }
}

#Preview {
    RobotMissionView(item: FMTItem.seed[0])
        .environmentObject(SSHConnectionManager())
}
