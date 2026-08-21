// SettingsView.swift
// Settings screen — spec: README §7.8

import SwiftUI
import CoreHaptics

// MARK: - Settings model (@AppStorage-backed)

final class FMTSettings: ObservableObject {
    // Voice & Speech
    @AppStorage("verbosity")   var verbosity: Verbosity  = .standard
    @AppStorage("speechRate")  var speechRate: SpeechRate = .normal
    @AppStorage("voice")       var voice: VoiceChoice    = .default_

    // Haptics
    @AppStorage("hapticsOn")   var hapticsOn: Bool       = true
    @AppStorage("hapticIntensity") var hapticIntensity: HapticIntensity = .strong

    // Audio cues
    @AppStorage("sonarStyle")  var sonarStyle: SonarStyle = .ping
    @AppStorage("stereoPanning") var stereoPanning: Bool  = true
    @AppStorage("foundChime")  var foundChime: FoundChime = .chord
    @AppStorage("cueVolume")   var cueVolume: Double      = 0.8

    // Search preferences
    @AppStorage("sensitivity") var sensitivity: Sensitivity = .balanced
    @AppStorage("lowLightBoost") var lowLightBoost: Bool    = true
    @AppStorage("maxScanTime") var maxScanTime: MaxScanTime = .sixty

    enum Verbosity: String, CaseIterable {
        case concise = "Concise", standard = "Standard", detailed = "Detailed"
    }
    enum SpeechRate: String, CaseIterable {
        case slow = "Slow", normal = "Normal", fast = "Fast"
    }
    enum VoiceChoice: String, CaseIterable {
        case default_ = "Default", samantha = "Samantha", daniel = "Daniel"
        var displayName: String { rawValue == "Default" ? "Default" : rawValue }
    }
    enum HapticIntensity: String, CaseIterable {
        case soft = "Soft", medium = "Medium", strong = "Strong"
    }
    enum SonarStyle: String, CaseIterable {
        case ping = "Ping", beep = "Beep", sine = "Sine wave", voiceOnly = "Voice only"
    }
    enum FoundChime: String, CaseIterable {
        case chord = "Chord", tone = "Tone", none_ = "None"
        var displayName: String { rawValue == "None" ? "None" : rawValue }
    }
    enum Sensitivity: String, CaseIterable {
        case conservative = "Conservative", balanced = "Balanced", aggressive = "Aggressive"
    }
    enum MaxScanTime: String, CaseIterable {
        case thirty = "30 seconds", sixty = "60 seconds", ninety = "90 seconds"
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @StateObject private var settings = FMTSettings()
    @EnvironmentObject private var connectionManager: SSHConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var hapticPlayed = false

    var body: some View {
        NavigationStack {
            Form {
                voiceSpeechSection
                hapticsSection
                audioCuesSection
                cameraDetectionSection
                serverConnectionSection
                privacyHelpSection

                Section {
                    Text("RobotFind • v1.0")
                        .font(.system(size: 13))
                        .foregroundStyle(FMTTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                        .accessibilityHidden(true)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.body)
                        .accessibilityLabel("Done")
                        .accessibilityHint("Closes settings")
                }
            }
        }
    }

    private var serverConnectionSection: some View {
        Section {
            NavigationLink {
                ServerConnectionView()
            } label: {
                HStack {
                    Text("Server connection")
                    Spacer()
                    Text(connectionManager.state == .connected ? "Connected" : "Not connected")
                        .foregroundStyle(connectionManager.state == .connected ? .green : FMTTheme.textSecondary)
                }
            }
            .accessibilityLabel("Server connection, \(connectionManager.state.label)")
            .accessibilityHint("Opens the manual SSH connection form")
        } header: {
            SectionHeader("Server")
        }
    }

    // MARK: Voice & Speech

    private var voiceSpeechSection: some View {
        Section {
            PickerRow(
                label: "Verbosity",
                hint: "Changes how much spoken guidance you hear",
                selection: $settings.verbosity
            )
            PickerRow(
                label: "Speech rate",
                hint: "Adjusts the speed of spoken guidance",
                selection: $settings.speechRate
            )
            PickerRow(
                label: "Voice",
                hint: "Picks the spoken voice",
                selection: $settings.voice,
                displayValue: settings.voice.displayName
            )
        } header: {
            SectionHeader("Voice & Speech")
        }
    }

    // MARK: Haptics

    private var hapticsSection: some View {
        Section {
            ToggleRow(
                label: "Haptic feedback",
                hint: "Turns vibration cues on or off",
                isOn: $settings.hapticsOn
            )
            PickerRow(
                label: "Intensity",
                hint: "Adjusts how strong vibrations feel",
                selection: $settings.hapticIntensity
            )
            .disabled(!settings.hapticsOn)

            ActionRow(
                label: "Test haptic",
                hint: "Plays a sample vibration"
            ) {
                playTestHaptic()
            }
            .disabled(!settings.hapticsOn)
        } header: {
            SectionHeader("Haptics")
        }
    }

    // MARK: Audio cues

    private var audioCuesSection: some View {
        Section {
            PickerRow(
                label: "Sonar style",
                hint: "Pick the audio style for proximity feedback",
                selection: $settings.sonarStyle
            )
            ToggleRow(
                label: "Stereo panning",
                hint: "Pans audio left or right to indicate direction",
                isOn: $settings.stereoPanning
            )
            PickerRow(
                label: "Found chime",
                hint: "Sound played when an item is found",
                selection: $settings.foundChime,
                displayValue: settings.foundChime.displayName
            )
            VolumeRow(volume: $settings.cueVolume)
        } header: {
            SectionHeader("Audio cues")
        }
    }

    // MARK: Search Preferences

    private var cameraDetectionSection: some View {
        Section {
            PickerRow(
                label: "Sensitivity",
                hint: "Preserved for the next search flow",
                selection: $settings.sensitivity
            )
            ToggleRow(
                label: "Low-light boost",
                hint: "Preserved for teaching and future search flows",
                isOn: $settings.lowLightBoost
            )
            PickerRow(
                label: "Max scan time",
                hint: "Preserved for the next search flow",
                selection: $settings.maxScanTime
            )
        } header: {
            SectionHeader("Search preferences")
        }
    }

    // MARK: Privacy & Help

    private var privacyHelpSection: some View {
        Section {
            ActionRow(
                label: "All data is on this device",
                hint: "Learn what stays on your phone",
                showChevron: true
            ) {
                // TODO: show privacy detail sheet
            }
            ActionRow(
                label: "Replay onboarding",
                hint: "Plays the introduction again"
            ) {
                // TODO: present onboarding
            }
            ActionRow(
                label: "Tutorial videos",
                hint: "Watch audio-described tutorials",
                showChevron: true
            ) {
                // TODO: open tutorials
            }
            ActionRow(
                label: "Send feedback",
                hint: "Contact the developers",
                showChevron: true
            ) {
                // TODO: compose feedback
            }
        } header: {
            SectionHeader("Privacy & Help")
        }
    }

    // MARK: - Haptic test

    private func playTestHaptic() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        UIAccessibility.post(notification: .announcement, argument: "Haptic played.")
    }
}

// MARK: - Row sub-views

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .kerning(0.5)
            .textCase(.uppercase)
            .foregroundStyle(FMTTheme.textSecondary)
    }
}

private struct ToggleRow: View {
    let label: String
    let hint: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .font(.body)
        }
        .frame(minHeight: 56)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct PickerRow<T: RawRepresentable & CaseIterable & Hashable>: View
where T.RawValue == String, T.AllCases: RandomAccessCollection {
    let label: String
    let hint: String
    @Binding var selection: T
    var displayValue: String? = nil

    var body: some View {
        NavigationLink {
            PickerDetailView(label: label, selection: $selection)
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 17))
                    .foregroundStyle(FMTTheme.text)
                Spacer()
                Text(displayValue ?? selection.rawValue)
                    .font(.system(size: 16))
                    .foregroundStyle(FMTTheme.textSecondary)
            }
            .frame(minHeight: 56)
        }
        .accessibilityLabel("\(label), \(displayValue ?? selection.rawValue)")
        .accessibilityHint(hint)
    }
}

private struct ActionRow: View {
    let label: String
    let hint: String
    var showChevron: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 17))
                    .foregroundStyle(FMTTheme.text)
                Spacer()
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FMTTheme.textTertiary)
                }
            }
            .frame(minHeight: 56)
        }
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}

private struct VolumeRow: View {
    @Binding var volume: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Volume")
                    .font(.system(size: 17))
                Spacer()
                Text("\(Int(volume * 100))%")
                    .font(.system(size: 16))
                    .foregroundStyle(FMTTheme.textSecondary)
            }
            Slider(value: $volume, in: 0...1, step: 0.05) {
                Text("Volume")
            } minimumValueLabel: {
                Image(systemName: "speaker.fill").foregroundStyle(FMTTheme.textTertiary)
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(FMTTheme.textTertiary)
            }
            .accentColor(FMTTheme.accent)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Volume")
        .accessibilityHint("Adjusts cue volume")
        .accessibilityValue("\(Int(volume * 100)) percent")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

// MARK: - Generic picker detail page

private struct PickerDetailView<T: RawRepresentable & CaseIterable & Hashable>: View
where T.RawValue == String, T.AllCases: RandomAccessCollection {
    let label: String
    @Binding var selection: T
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(T.allCases, id: \.self) { option in
            Button {
                selection = option
                dismiss()
            } label: {
                HStack {
                    Text(option.rawValue)
                        .font(.system(size: 17))
                        .foregroundStyle(FMTTheme.text)
                    Spacer()
                    if selection == option {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(FMTTheme.accent)
                    }
                }
                .frame(minHeight: 56)
            }
            .accessibilityLabel(option.rawValue)
            .accessibilityAddTraits(selection == option ? [.isSelected] : [])
        }
        .navigationTitle(label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SSHConnectionManager())
}
