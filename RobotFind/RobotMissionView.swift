import SwiftUI

@MainActor
final class RobotMissionViewModel: ObservableObject {
    @Published private(set) var currentMission: Mission?
    @Published private(set) var isStarting = false
    @Published var errorMessage: String?

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
        } catch {
            errorMessage = error.localizedDescription
            print("[Mission] failed: \(String(reflecting: error))")
        }
        isStarting = false
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

                Image(systemName: viewModel.currentMission?.state == .failed ? "exclamationmark.triangle" : "figure.walk")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(viewModel.currentMission?.state == .failed ? FMTTheme.error : FMTTheme.accent)
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
        }
    }

    private func missionStateText(_ state: MissionState) -> String {
        switch state {
        case .ready: return "Mission ready"
        case .starting: return "Starting robot search..."
        case .running: return "Robot search running"
        case .stopping: return "Stopping robot search..."
        case .stopped: return "Robot search stopped"
        case .failed: return "Robot search failed"
        }
    }
}

#Preview {
    RobotMissionView(item: FMTItem.seed[0])
        .environmentObject(SSHConnectionManager())
}
