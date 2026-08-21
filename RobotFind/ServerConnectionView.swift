import SwiftUI

struct ServerConnectionView: View {
    @EnvironmentObject private var connectionManager: SSHConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var server = ""
    @State private var sshPort = String(ServerConnectionConfig.defaultSSHPort)
    @State private var username = ""
    @State private var password = ""
    @State private var qwenAPIPort = String(ServerConnectionConfig.defaultQwenAPIPort)
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server address", text: $server)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityLabel("Server")
                    TextField("22", text: $sshPort)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("SSH port")
                } header: {
                    Text("SSH connection")
                }

                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Username")
                    SecureField("Password", text: $password)
                        .accessibilityLabel("Password")
                }

                Section {
                    TextField("8000", text: $qwenAPIPort)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Qwen API port")
                } header: {
                    Text("Qwen API")
                } footer: {
                    Text("The API port is on the server and can differ from the SSH port.")
                }

                Section {
                    Button {
                        connect()
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking { ProgressView().padding(.trailing, 8) }
                            Text(isWorking ? "Connecting..." : "Connect")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(isWorking)
                    .accessibilityLabel(isWorking ? "Connecting" : "Connect")

                    if case .connected = connectionManager.state {
                        Button("Disconnect", role: .destructive) {
                            Task { await connectionManager.disconnect() }
                        }
                    }
                }

                Section {
                    Label(connectionManager.state.label,
                          systemImage: connectionManager.state == .connected ? "checkmark.circle.fill" : "network")
                        .foregroundStyle(connectionManager.state == .connected ? .green : FMTTheme.text)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Connection status: \(connectionManager.state.label)")
                }
            }
            .navigationTitle("Connect to Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: connectionManager.state) { _, newState in
                isWorking = [.connecting, .authenticating, .forwarding, .checkingHealth].contains(where: { state in
                    switch (state, newState) {
                    case (.connecting, _), (.authenticating, _), (.forwarding, _), (.checkingHealth, _): return true
                    default: return false
                    }
                })
            }
        }
    }

    private func connect() {
        guard let sshPort = Int(sshPort), let qwenAPIPort = Int(qwenAPIPort) else {
            return
        }
        let config = ServerConnectionConfig(
            host: server.trimmingCharacters(in: .whitespacesAndNewlines),
            sshPort: sshPort,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            remoteAPIPort: qwenAPIPort
        )
        isWorking = true
        Task {
            await connectionManager.connectAndCheckHealth(config: config)
            password = ""
            isWorking = false
        }
    }
}
