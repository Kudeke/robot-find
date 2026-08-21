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
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Server") {
                        TextField("IP address or hostname", text: $server)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Server address")
                    }
                    LabeledContent("SSH Port") {
                        TextField("22", text: $sshPort)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("SSH port")
                    }
                } header: {
                    Text("SSH connection")
                }

                Section {
                    LabeledContent("Username") {
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Username")
                    }
                    LabeledContent("Password") {
                        SecureField("Required", text: $password)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Password")
                    }
                }

                Section {
                    LabeledContent("Qwen API Port") {
                        TextField("8000", text: $qwenAPIPort)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Qwen API port")
                    }
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
                    HStack(spacing: 12) {
                        if isWorking {
                            ProgressView()
                        } else {
                            Image(systemName: connectionManager.state == .connected ? "checkmark.circle.fill" : "network")
                                .foregroundStyle(connectionManager.state == .connected ? .green : FMTTheme.text)
                        }
                        Text(connectionManager.state.label)
                            .foregroundStyle(connectionManager.state == .connected ? .green : FMTTheme.text)
                    }
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
                let activeStates: [SSHConnectionState] = [.connecting, .authenticating, .forwarding, .checkingHealth]
                isWorking = activeStates.contains(where: { state in
                    switch (state, newState) {
                    case (.connecting, _), (.authenticating, _), (.forwarding, _), (.checkingHealth, _): return true
                    default: return false
                    }
                })
            }
            .alert("Connection failed", isPresented: Binding(
                get: { connectionManager.state.isFailed },
                set: { _ in }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(connectionManager.state.label)
            }
            .alert("Invalid connection details", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("OK", role: .cancel) { validationMessage = nil }
            } message: {
                Text(validationMessage ?? "Check the connection fields.")
            }
        }
    }

    private func connect() {
        guard let sshPort = Int(sshPort), let qwenAPIPort = Int(qwenAPIPort) else {
            validationMessage = "SSH Port and Qwen API Port must contain numbers only. Enter the server address in Server and a number such as 22 in SSH Port."
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
        Task { @MainActor in
            await connectionManager.connectAndCheckHealth(config: config)
            password = ""
            isWorking = false
        }
    }
}

private extension SSHConnectionState {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
