// TeachWizardView.swift
// Teach wizard — 5 steps with four guided image-capture views.

import SwiftUI
import ARKit
import AVFoundation
import SceneKit
import UIKit

// MARK: - Teach camera model (camera preview + guided capture)

final class TeachCameraModel: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    @Published var hasCameraInput = false
    @Published private(set) var distanceProgress: Double = 0
    @Published private(set) var anchorVisibilityProgress: Double = 0
    @Published private(set) var isAnchorInView = false
    @Published private(set) var guidanceText = "Center the item to begin guided capture."

    private let sessionQueue = DispatchQueue(label: "com.fmt.teach", qos: .userInitiated)
    private let targetDistanceMeters: Float = 0.40
    private let anchorPlacementDistanceMeters: Float = 0.01
    private let maximumCaptureDuration: TimeInterval = 15
    private var teachingAnchor: ARAnchor?
    private var captureAnchorPosition: SIMD3<Float>?
    private var captureStartedAt: Date?
    private var requiredAnchorVisibilityDuration: TimeInterval = 4
    private var anchorVisibleDuration: TimeInterval = 0
    private var lastFrameTimestamp: TimeInterval?
    private var lastVisibilityMilestone = 0
    private var captureCompletion: ((Result<FinalizedTeachVideo, Error>) -> Void)?
    private var videoRecorder: TeachVideoRecorder?
    private var captureWorkItem: DispatchWorkItem?
    private var lastSpokenGuidance = ""
    private var lastHapticGuidance = ""
    private let speechSynthesizer = AVSpeechSynthesizer()

    func setup() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        session.delegate = self
        session.delegateQueue = sessionQueue
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        sessionQueue.async { [weak self] in
            self?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            DispatchQueue.main.async { self?.hasCameraInput = true }
        }
    }

    // Call from main thread; completion is called on the main thread.
    func capture(duration: TimeInterval,
                 itemID: String,
                 clipIndex: Int,
                 completion: @escaping (Result<FinalizedTeachVideo, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureWorkItem?.cancel()
            if let anchor = self.teachingAnchor {
                self.session.remove(anchor: anchor)
            }
            self.teachingAnchor = nil
            self.captureAnchorPosition = nil
            self.captureStartedAt = Date()
            self.requiredAnchorVisibilityDuration = duration
            self.anchorVisibleDuration = 0
            self.lastFrameTimestamp = nil
            self.lastVisibilityMilestone = 0
            self.captureCompletion = completion
            DispatchQueue.main.async {
                self.anchorVisibilityProgress = 0
                self.isAnchorInView = false
            }
            do {
                let recorder = TeachVideoRecorder()
                try recorder.startRecording(itemID: itemID, clipIndex: clipIndex)
                self.videoRecorder = recorder
            } catch {
                self.captureStartedAt = nil
                self.captureCompletion = nil
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.captureStartedAt != nil else { return }
                self.finishCapture(with: self.captureTimeoutError())
            }
            self.captureWorkItem = workItem
            self.sessionQueue.asyncAfter(deadline: .now() + self.maximumCaptureDuration, execute: workItem)
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if captureStartedAt != nil, teachingAnchor == nil {
            placeTeachingAnchor(from: frame)
        }
        let anchorVisible = updateAnchorVisibility(from: frame)
        let distanceReady = updateDistanceGuidance(from: frame, anchorVisible: anchorVisible)

        guard let startedAt = captureStartedAt,
              let videoRecorder else { return }
        do {
            try videoRecorder.append(frame: frame)
            if anchorVisibleDuration >= requiredAnchorVisibilityDuration && distanceReady {
                finishCapture()
            } else if Date().timeIntervalSince(startedAt) >= maximumCaptureDuration {
                finishCapture(with: captureTimeoutError())
            }
        } catch {
            captureWorkItem?.cancel()
            captureStartedAt = nil
            videoRecorder.cancel()
            self.videoRecorder = nil
            let completion = captureCompletion
            captureCompletion = nil
            DispatchQueue.main.async { completion?(.failure(error)) }
        }
    }

    private func finishCapture(with error: Error? = nil) {
        guard captureStartedAt != nil else { return }
        captureStartedAt = nil
        captureWorkItem?.cancel()

        if let error {
            videoRecorder?.cancel()
            videoRecorder = nil
            let completion = captureCompletion
            captureCompletion = nil
            let visibleSeconds = String(format: "%.2f", anchorVisibleDuration)
            let distancePercent = String(format: "%.2f", distanceProgress * 100)
            print("[TeachVideo] capture timed out after \(maximumCaptureDuration)s visible=\(visibleSeconds)s distanceProgress=\(distancePercent)%")
            DispatchQueue.main.async { completion?(.failure(error)) }
            return
        }

        videoRecorder?.finish { [weak self] result in
            guard let self else { return }
            self.sessionQueue.async {
                self.videoRecorder = nil
                let completion = self.captureCompletion
                self.captureCompletion = nil
                DispatchQueue.main.async { completion?(result) }
            }
        }
    }

    private func captureTimeoutError() -> TeachVideoRecorderError {
        if anchorVisibleDuration < requiredAnchorVisibilityDuration {
            return .anchorVisibilityTimedOut
        }
        return .distanceGuidanceTimedOut
    }

    func stop() {
        sessionQueue.async { [weak self] in
            if let anchor = self?.teachingAnchor {
                self?.session.remove(anchor: anchor)
            }
            self?.teachingAnchor = nil
            self?.captureAnchorPosition = nil
            self?.captureWorkItem?.cancel()
            self?.captureStartedAt = nil
            self?.videoRecorder?.cancel()
            self?.videoRecorder = nil
            self?.captureCompletion = nil
            DispatchQueue.main.async {
                self?.distanceProgress = 0
                self?.anchorVisibilityProgress = 0
                self?.isAnchorInView = false
                self?.guidanceText = "Center the item to begin guided capture."
            }
            self?.session.pause()
        }
    }

    private func placeTeachingAnchor(from frame: ARFrame) {
        var transform = frame.camera.transform
        let forwardOffset = frame.camera.transform * SIMD4<Float>(0, 0, -anchorPlacementDistanceMeters, 0)
        transform.columns.3 += forwardOffset

        let anchor = ARAnchor(name: "RobotFindTeachingAnchor", transform: transform)
        teachingAnchor = anchor
        captureAnchorPosition = transform.translation
        session.add(anchor: anchor)
        print("[TeachCapture] AR teaching anchor placed near camera distance=\(anchorPlacementDistanceMeters)m")
    }

    private func updateDistanceGuidance(from frame: ARFrame, anchorVisible: Bool) -> Bool {
        guard let anchorPosition = captureAnchorPosition else { return false }
        let cameraPosition = frame.camera.transform.translation
        let distance = simd_distance(cameraPosition, anchorPosition)
        let movedDistance = max(0, distance - anchorPlacementDistanceMeters)
        let clampedProgress = min(1, Double(movedDistance / targetDistanceMeters))
        let text: String
        if captureStartedAt != nil && !anchorVisible {
            text = "Keep the reference point in view."
        } else if captureStartedAt != nil && clampedProgress < 1 {
            text = movedDistance < 0.05
                ? "Slowly pull the phone away from the item."
                : "Keep moving slowly around the item."
        } else if captureStartedAt != nil {
            text = "Good movement. Hold steady."
        } else {
            text = "Good distance. Tap capture when ready."
        }

        DispatchQueue.main.async { [weak self] in
            self?.distanceProgress = Double(clampedProgress)
            self?.guidanceText = text
        }
        speakAndHapticIfNeeded(text)
        return clampedProgress >= 1
    }

    private func updateAnchorVisibility(from frame: ARFrame) -> Bool {
        guard let anchorPosition = captureAnchorPosition else { return false }
        let visible = isAnchorVisible(anchorPosition, in: frame)

        if captureStartedAt != nil, let previousTimestamp = lastFrameTimestamp {
            let delta = frame.timestamp - previousTimestamp
            if visible, delta > 0 {
                anchorVisibleDuration += min(delta, 0.2)
            }
        }
        lastFrameTimestamp = frame.timestamp

        let progress = min(1, anchorVisibleDuration / requiredAnchorVisibilityDuration)
        let milestone = captureStartedAt == nil ? 0 : Int(progress * 2)
        if captureStartedAt != nil, milestone > lastVisibilityMilestone {
            lastVisibilityMilestone = milestone
            DispatchQueue.main.async {
                UIImpactFeedbackGenerator(style: milestone == 2 ? .medium : .light).impactOccurred()
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.isAnchorInView = visible
            self?.anchorVisibilityProgress = progress
        }
        return visible
    }

    private func isAnchorVisible(_ anchorPosition: SIMD3<Float>, in frame: ARFrame) -> Bool {
        let cameraPoint = frame.camera.transform.inverse * SIMD4<Float>(
            anchorPosition.x,
            anchorPosition.y,
            anchorPosition.z,
            1
        )
        guard cameraPoint.z < 0 else { return false }

        let viewportSize = UIScreen.main.bounds.size
        let screenPoint = frame.camera.projectPoint(
            anchorPosition,
            orientation: .portrait,
            viewportSize: viewportSize
        )
        let margin: CGFloat = 24
        return screenPoint.x >= -margin
            && screenPoint.x <= viewportSize.width + margin
            && screenPoint.y >= -margin
            && screenPoint.y <= viewportSize.height + margin
    }

    private func speakAndHapticIfNeeded(_ text: String) {
        guard text != lastSpokenGuidance else { return }
        lastSpokenGuidance = text
        DispatchQueue.main.async {
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = 0.48
            self.speechSynthesizer.stopSpeaking(at: .word)
            self.speechSynthesizer.speak(utterance)
            UIAccessibility.post(notification: .announcement, argument: text)
            if text != self.lastHapticGuidance {
                self.lastHapticGuidance = text
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }
}

private extension simd_float4x4 {
    var translation: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }

    var forward: SIMD3<Float> {
        SIMD3<Float>(-columns.2.x, -columns.2.y, -columns.2.z)
    }
}

// MARK: - Completion payload

struct TeachResult {
    let itemID: String
    let name: String
    let tryFind: Bool
    let objectProfile: ObjectProfile?
}

struct TeachWizardView: View {
    var presetName: String = ""
    var onCancel: () -> Void = {}
    var onComplete: (TeachResult) -> Void = { _ in }

    @EnvironmentObject private var connectionManager: SSHConnectionManager

    @State private var step = 1
    @State private var itemName = ""
    @State private var clipsRecorded = 0
    @State private var isRecording = false
    @State private var analysisState: TeachAnalysisState = .idle
    @State private var analyzedProfile: ObjectProfile?
    @State private var analysisCanRetry = false
    @State private var storageFull = false
    @State private var micAllowed = true

    // Camera guidance
    @State private var itemID = UUID().uuidString
    @StateObject private var teachCamera = TeachCameraModel()

    private let totalSteps = 5
    private let angles = ["Front view", "Side view", "Top view", "Different background"]

    // MARK: - Body

    var body: some View {
        if storageFull {
            VStack {
                Spacer()
                StorageFullView(onGoToLibrary: onCancel)
                Spacer()
            }
            .background(FMTTheme.background)
        } else {
            ZStack(alignment: .top) {
                stepBackground
                VStack(spacing: 0) {
                    stepChrome
                    stepContent
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                itemName = presetName
                storageFull = isStorageFull()
                micAllowed = AVAudioSession.sharedInstance().recordPermission == .granted
            }
            .onChange(of: step) { _, newStep in
                let stepNames = ["", "Name your item", "Tips for capture", "Capture guided views", "Saving recordings", "Done"]
                let name = stepNames.indices.contains(newStep) ? stepNames[newStep] : "Step \(newStep)"
                UIAccessibility.post(notification: .screenChanged, argument: "Step \(newStep) of \(totalSteps). \(name).")
                if newStep == 3 { teachCamera.setup() }
                if newStep != 3 { teachCamera.stop() }
            }
        }
    }

    private func isStorageFull() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()),
              let free = attrs[.systemFreeSize] as? Int64 else { return false }
        return free < 100 * 1024 * 1024   // < 100 MB
    }

    // MARK: - Background colour per step

    private var stepBackground: some View {
        Group {
            if step == 3 {
                Color.black
            } else {
                FMTTheme.background
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Common chrome: Cancel/Back + Step pill + Progress bar

    private var stepChrome: some View {
        VStack(spacing: 12) {
            HStack {
                // Cancel (step 1) or Back (steps 2-5)
                Button {
                    if step == 1 { onCancel() } else { step -= 1 }
                } label: {
                    Image(systemName: step == 1 ? "xmark" : "chevron.left")
                        .font(.system(size: step == 1 ? 18 : 16, weight: .semibold))
                        .foregroundStyle(step == 3 ? .white : FMTTheme.text)
                        .frame(width: 48, height: 48)
                        .background((step == 3 ? Color.white : Color.black).opacity(0.07))
                        .clipShape(Circle())
                }
                .accessibilityLabel(step == 1 ? "Cancel" : "Back")
                .accessibilityHint(step == 1 ? "Cancels teaching" : "Goes back a step")

                Spacer()

                Text("Step \(step) of \(totalSteps)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(step == 3 ? Color.white.opacity(0.7) : FMTTheme.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Step \(step) of \(totalSteps)")

                Spacer()
                // Mirror spacer to centre the pill
                Color.clear.frame(width: 48, height: 48)
            }

            // 5-segment progress bar
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { n in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(n <= step ? FMTTheme.accent : (step == 3 ? Color.white.opacity(0.18) : FMTTheme.separator))
                        .frame(height: 6)
                        .animation(.easeInOut(duration: 0.25), value: step)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 4)
    }

    // MARK: - Step dispatcher

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 1: step1
        case 2: step2
        case 3: step3
        case 4: step4
        default: step5
        }
    }

    // MARK: ─ Step 1: Name ─────────────────────────────────────────────────

    private let suggestions = ["Keys", "Wallet", "White cane", "Headphones",
                                "Mug", "Remote", "Phone charger", "Medication"]

    private var step1: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Name your item")
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(FMTTheme.text)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 12)

                    Text("What do you want to call this item? You can dictate by tapping the microphone.")
                        .font(.system(size: 17))
                        .foregroundStyle(FMTTheme.textSecondary)
                        .lineSpacing(3)
                        .padding(.top, 12)

                    // Text field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ITEM NAME")
                            .font(.system(size: 14, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(FMTTheme.textSecondary)

                        HStack(spacing: 12) {
                            TextField("e.g. Red coffee mug", text: $itemName)
                                .font(.system(size: 22, weight: .semibold))
                                .tracking(-0.3)
                                .submitLabel(.done)
                                .accessibilityLabel("Item name input")
                                .accessibilityHint("Type or dictate the name of your item")

                            if micAllowed {
                                Button {
                                    // TODO: activate dictation
                                } label: {
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(FMTTheme.accent)
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Dictate")
                                .accessibilityHint("Starts voice input")
                            }
                        }
                        .padding(18)
                        .background(FMTTheme.fieldBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(FMTTheme.accent, lineWidth: 2)
                        )
                    }
                    .padding(.top, 24)

                    // Suggestion chips
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SUGGESTIONS")
                            .font(.system(size: 14, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(FMTTheme.textSecondary)

                        FlowLayout(spacing: 10) {
                            ForEach(suggestions, id: \.self) { s in
                                Button { itemName = s } label: {
                                    Text(s)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(FMTTheme.chipText)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(FMTTheme.chipBg)
                                        .clipShape(Capsule())
                                }
                                .frame(minHeight: 44)
                                .accessibilityLabel("Suggestion: \(s)")
                                .accessibilityHint("Sets the name to \(s)")
                            }
                        }
                    }
                    .padding(.top, 28)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            // Bottom CTA
            bottomButton(
                label: "Next",
                hint: "Goes to setup, step 2 of 5",
                enabled: !itemName.trimmingCharacters(in: .whitespaces).isEmpty
            ) { step = 2 }
        }
    }

    // MARK: ─ Step 2: Get ready ────────────────────────────────────────────

    private let tips = [
        "Use a contrasting background — a plain table works well.",
        "Hold the phone about one foot away.",
        "You\u{2019}ll capture 4 short guided views from different angles.",
        "Each guided view takes at least 4 seconds with the reference point visible.",
    ]

    private var step2: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Get ready")
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(FMTTheme.text)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 12)

                    (Text("Place ")
                     + Text(itemName.isEmpty ? "your item" : itemName).bold().foregroundColor(FMTTheme.text)
                     + Text(" on a flat surface in good lighting. Make sure nothing else cluttered is around it. Tell me when you\u{2019}re ready."))
                        .font(.system(size: 19))
                        .foregroundStyle(FMTTheme.textSecondary)
                        .lineSpacing(3)
                        .padding(.top, 12)

                    // Tips card
                    VStack(alignment: .leading, spacing: 0) {
                        Text("TIPS")
                            .font(.system(size: 14, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(FMTTheme.text)
                            .padding(.bottom, 12)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(tips, id: \.self) { tip in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(FMTTheme.successBg)
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(FMTTheme.success)
                                        )
                                        .flexibleFrame(minWidth: 24, maxWidth: 24)
                                    Text(tip)
                                        .font(.system(size: 16))
                                        .foregroundStyle(FMTTheme.text)
                                        .lineSpacing(2)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(FMTTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.top, 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            // Bottom CTAs
            VStack(spacing: 10) {
                bottomButton(label: "I\u{2019}m ready",
                             hint: "Starts guided image capture, step 3 of 5",
                             enabled: true) {
                    clipsRecorded = 0
                    beginCaptureSession()
                    step = 3
                }
                Button {
                    clipsRecorded = 0
                    beginCaptureSession()
                    step = 3
                } label: {
                    Text("Get help framing")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(FMTTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Get help framing")
                .accessibilityHint("Uses the camera to verify the item is centred with audio guidance")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    // MARK: ─ Step 3: Capture 4 guided views ──────────────────────────────

    private var step3: some View {
        let currentAngle = angles[min(clipsRecorded, 3)]
        let allDone = clipsRecorded >= 4

        return VStack(spacing: 0) {
            // Angle label
            VStack(spacing: 6) {
            Text("View \(min(clipsRecorded + 1, 4)) of 4")
                    .font(.system(size: 14, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(allDone ? "All 4 guided views captured" : currentAngle)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Color.white)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            // Viewfinder
            viewfinder(allDone: allDone)
                .padding(.horizontal, 20)

            // Clip progress bars
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i < clipsRecorded ? Color(hex: 0x34C759) : Color.white.opacity(0.18))
                        .frame(height: 6)
                        .animation(.easeInOut(duration: 0.3), value: clipsRecorded)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(clipsRecorded) of 4 guided views captured")

            // Capture button + status + Next
            VStack(spacing: 14) {
                RecordButton(isRecording: isRecording, isDone: allDone, clipIndex: clipsRecorded) {
                    guard !isRecording && !allDone else { return }
                    startRecording()
                }

                Text(allDone ? "Tap Prepare item to finish capture"
                     : (isRecording ? "Capturing\u{2026}" : "Tap to capture"))
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .accessibilityAddTraits(.updatesFrequently)

                // Finish / Next
                Button {
                    if allDone {
                        step = 4
                        startPreparingItem()
                    }
                } label: {
                    Text(allDone ? "Recording complete" : "Next")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(allDone ? FMTTheme.onAccent : FMTTheme.onAccent.opacity(0.45))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(allDone ? FMTTheme.accent : FMTTheme.accent.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
                }
                .disabled(!allDone)
                .accessibilityLabel(allDone ? "Recording complete" : "Next")
                .accessibilityHint(allDone
                    ? "Verifies the four recordings, step 4 of 5"
                    : "Continues when all 4 guided views are captured")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    @ViewBuilder
    private func viewfinder(allDone: Bool) -> some View {
        ZStack {
            // Real camera preview when available, dark gradient fallback
            if teachCamera.hasCameraInput {
                CameraPreviewView(session: teachCamera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            } else {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0x2a2a30), Color(hex: 0x0a0a0c)],
                            center: UnitPoint(x: 0.5, y: 0.4),
                            startRadius: 0, endRadius: 300
                        )
                    )
                // Mock item shown only in simulator fallback
                RoundedRectangle(cornerRadius: 28)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0xC73E3A), Color(hex: 0x7A1F1C)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(Double(clipsRecorded) * 22))
                    .animation(.easeInOut(duration: 0.4), value: clipsRecorded)
            }

            // Framing brackets (yellow)
            FramingBrackets()

            // REC pill
            if isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .opacity(isRecording ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: isRecording)
                    Text("REC")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(red: 1, green: 0.23, blue: 0.19).opacity(0.9))
                .clipShape(Capsule())
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 20)
            }

            // Distance-based coaching caption and progress
            VStack(spacing: 8) {
                Text(teachCamera.guidanceText)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)

                ProgressView(value: teachCamera.distanceProgress)
                    .tint(teachCamera.distanceProgress >= 0.7 ? Color.green : Color.yellow)
                    .frame(width: 150)
                    .accessibilityLabel("Distance guidance")
                    .accessibilityValue("\(Int(teachCamera.distanceProgress * 100)) percent")

                if isRecording {
                    ProgressView(value: teachCamera.anchorVisibilityProgress)
                        .tint(teachCamera.isAnchorInView ? Color.green : Color.orange)
                        .frame(width: 150)
                        .accessibilityLabel("Reference point visibility")
                        .accessibilityValue("\(Int(teachCamera.anchorVisibilityProgress * 100)) percent of the required 4 seconds")
                }
            }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityLabel("Live distance guidance: \(teachCamera.guidanceText)")
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.75, contentMode: .fit)
    }

    // MARK: ─ Step 4: Preparing ────────────────────────────────────────────

    private var step4: some View {
        VStack(spacing: 0) {
            Spacer()

            if case .failed(let message) = analysisState {
                VStack(spacing: 24) {
                    Circle()
                        .fill(Color(hex: 0xFFEAEA))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48, weight: .semibold))
                                .foregroundStyle(FMTTheme.error)
                        )
                        .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        Text("Something went wrong")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(FMTTheme.text)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)

                        Text(message)
                            .font(.system(size: 17))
                            .foregroundStyle(FMTTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                }
                .padding(.horizontal, 28)

                Spacer()

                bottomButton(
                    label: analysisCanRetry ? "Retry analysis" : "Retry guided views",
                    hint: analysisCanRetry ? "Retries server analysis using the saved recordings" : "Goes back to the guided capture step",
                    systemImage: "arrow.counterclockwise",
                    enabled: true
                ) {
                    if analysisCanRetry {
                        startPreparingItem()
                    } else {
                        clipsRecorded = 0
                        beginCaptureSession()
                        step = 3
                    }
                }
            } else {
                VStack(spacing: 28) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(FMTTheme.accent)
                        .frame(width: 120, height: 120)
                        .background(FMTTheme.chipBg)
                        .clipShape(Circle())
                        .accessibilityLabel("Analyzing your item")
                        .accessibilityAddTraits(.updatesFrequently)

                    VStack(spacing: 10) {
                        Text(analysisState == .validatingVideos ? "Checking recordings\u{2026}" : "Analyzing your item\u{2026}")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(FMTTheme.text)
                            .accessibilityAddTraits(.isHeader)

                        Text("Your four recordings are being sent securely through the connected server tunnel. This may take a moment.")
                            .font(.system(size: 19))
                            .foregroundStyle(FMTTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                }
                .padding(.horizontal, 28)

                Spacer()
            }
        }
    }

    // MARK: ─ Step 5: Try it now ───────────────────────────────────────────

    private var step5: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Circle()
                    .fill(FMTTheme.successBg)
                    .frame(width: 140, height: 140)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 64, weight: .bold))
                            .foregroundStyle(FMTTheme.success)
                    )
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("All set")
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(FMTTheme.text)
                        .accessibilityAddTraits(.isHeader)

                    (Text("I can now find your ")
                     + Text(itemName.isEmpty ? "item" : itemName).bold().foregroundColor(FMTTheme.text)
                     + Text(". Want to try the next search flow?"))
                        .font(.system(size: 19))
                        .foregroundStyle(FMTTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                if let profile = analyzedProfile {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(profile.category)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(FMTTheme.accent)
                        Text(profile.visualDescription)
                            .font(.system(size: 16))
                            .foregroundStyle(FMTTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !profile.distinctiveFeatures.isEmpty {
                            Text("Distinctive features: \(profile.distinctiveFeatures.joined(separator: ", "))")
                                .font(.system(size: 16))
                                .foregroundStyle(FMTTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(FMTTheme.chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Category: \(profile.category). \(profile.visualDescription). Distinctive features: \(profile.distinctiveFeatures.joined(separator: ", "))")
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 12) {
                bottomButton(
                    label: "Try finding it now",
                    hint: "Goes to the temporary search screen with this item selected",
                    systemImage: "magnifyingglass",
                    enabled: true
                ) {
                    onComplete(TeachResult(itemID: itemID, name: itemName.isEmpty ? "New item" : itemName, tryFind: true, objectProfile: analyzedProfile))
                }

                Button {
                    onComplete(TeachResult(itemID: itemID, name: itemName.isEmpty ? "New item" : itemName, tryFind: false, objectProfile: analyzedProfile))
                } label: {
                    Text("Save and finish")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(FMTTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(FMTTheme.chipBg)
                        .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .accessibilityLabel("Save and finish")
                .accessibilityHint("Saves the item and returns Home")
            }
            .padding(.bottom, 28)
        }
    }

    // MARK: - Shared bottom button

    @ViewBuilder
    private func bottomButton(
        label: String,
        hint: String,
        systemImage: String? = nil,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon = systemImage {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 22, weight: .semibold))
            }
            .foregroundStyle(enabled ? FMTTheme.onAccent : FMTTheme.onAccent.opacity(0.45))
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(enabled ? FMTTheme.accent : FMTTheme.accent.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
        }
        .disabled(!enabled)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    // MARK: - Timers

    private func startRecording() {
        isRecording = true
        UIAccessibility.post(notification: .announcement, argument: "Guided capture started.")
        teachCamera.capture(duration: 4.0, itemID: itemID, clipIndex: clipsRecorded + 1) { result in
            isRecording = false
            switch result {
            case .success(let video):
                clipsRecorded = min(4, clipsRecorded + 1)
                let remaining = 4 - clipsRecorded
                print("[TeachVideo] recording stopped clip=\(clipsRecorded) duration=\(video.duration) size=\(video.fileSize)")
                let msg = remaining > 0
                    ? "\(clipsRecorded) of 4 recordings saved. \(remaining) remaining."
                    : "All 4 recordings saved. Tap Recording complete."
                UIAccessibility.post(notification: .announcement, argument: msg)
            case .failure(let error):
                print("[TeachVideo] recording failed: \(error.localizedDescription)")
                UIAccessibility.post(notification: .announcement,
                                     argument: "The video could not be saved. Please try this view again.")
            }
        }
    }

    private func beginCaptureSession() {
        do {
            try TeachCaptureStore.shared.startSession(itemID: itemID)
            analysisState = .idle
            analyzedProfile = nil
            analysisCanRetry = false
        } catch {
            analysisState = .failed("The capture folder could not be prepared. Please try again.")
            analysisCanRetry = false
            print("[TeachCapture] session failed: \(error.localizedDescription)")
            UIAccessibility.post(notification: .announcement,
                                 argument: "The capture folder could not be prepared. Please try again.")
        }
    }

    private func startPreparingItem() {
        guard !analysisState.isWorking else { return }
        analysisState = .validatingVideos
        analysisCanRetry = false

        Task { @MainActor in
            do {
                guard clipsRecorded >= 4 else {
                    throw TeachCaptureError.incompleteClips(clipsRecorded)
                }
                let clips = try TeachCaptureStore.shared.validateClips(itemID: itemID)
                print("[TeachVideo] teaching complete clips=\(clips.count)")
                for clip in clips {
                    print("[TeachVideo] finalized \(clip.url.lastPathComponent) duration=\(clip.duration) size=\(clip.fileSize)")
                }

                try await connectionManager.revalidateConnection()
                guard let baseURL = connectionManager.localBaseURL else {
                    throw ServerAPIError.disconnected
                }

                analysisState = .analyzing
                UIAccessibility.post(notification: .announcement, argument: "Analyzing your item. This may take a moment.")
                let profile = try await ServerAPI(baseURL: baseURL).createObject(
                    name: itemName.trimmingCharacters(in: .whitespacesAndNewlines),
                    videoURLs: clips.map(\.url)
                )
                analyzedProfile = profile
                analysisState = .completed(profile)
                analysisCanRetry = false
                UIAccessibility.post(notification: .announcement, argument: "Item analysis complete.")
                step = 5
            } catch let error as TeachCaptureError {
                analysisCanRetry = false
                analysisState = .failed("One or more recordings are missing or invalid. Please record the guided views again.")
                print("[ObjectUpload] video validation failed: \(error.localizedDescription)")
                UIAccessibility.post(notification: .announcement, argument: "The recorded videos could not be found. Please record the item again.")
            } catch {
                analysisCanRetry = true
                analysisState = .failed(error.localizedDescription)
                print("[ObjectUpload] failed: \(error.localizedDescription)")
                UIAccessibility.post(notification: .announcement, argument: "The server could not analyze this item. You can retry.")
            }
        }
    }
}

// MARK: - Camera preview (UIViewRepresentable)

private struct CameraPreviewView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> PreviewUIView { PreviewUIView(session: session) }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView, ARSCNViewDelegate {
        private let sceneView: ARSCNView

        init(session: ARSession) {
            sceneView = ARSCNView(frame: .zero, options: nil)
            super.init(frame: .zero)
            sceneView.session = session
            sceneView.scene = SCNScene()
            sceneView.delegate = self
            sceneView.automaticallyUpdatesLighting = false
            addSubview(sceneView)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sceneView.frame = bounds
            CATransaction.commit()
        }

        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard anchor.name == "RobotFindTeachingAnchor" else { return nil }

            let marker = SCNNode()
            marker.name = "RobotFindTeachingAnchorMarker"

            let center = SCNSphere(radius: 0.025)
            center.firstMaterial = markerMaterial()
            marker.addChildNode(SCNNode(geometry: center))

            let ring = SCNTorus(ringRadius: 0.05, pipeRadius: 0.004)
            ring.firstMaterial = markerMaterial()
            let ringNode = SCNNode(geometry: ring)
            ringNode.eulerAngles.x = .pi / 2
            marker.addChildNode(ringNode)

            marker.constraints = [SCNBillboardConstraint()]
            let pulse = SCNAction.sequence([
                SCNAction.scale(to: 1.18, duration: 0.7),
                SCNAction.scale(to: 0.92, duration: 0.7)
            ])
            marker.runAction(.repeatForever(pulse), forKey: "anchorPulse")
            return marker
        }

        private func markerMaterial() -> SCNMaterial {
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemYellow
            material.emission.contents = UIColor.systemYellow
            material.lightingModel = .constant
            return material
        }
    }
}

// MARK: - Capture button

private struct RecordButton: View {
    let isRecording: Bool
    let isDone: Bool
    let clipIndex: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 96, height: 96)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isRecording ? 6 : 38)
                        .fill(Color(red: 1, green: 0.23, blue: 0.19))
                        .frame(
                            width: isRecording ? 32 : 76,
                            height: isRecording ? 32 : 76
                        )
                        .animation(.easeInOut(duration: 0.2), value: isRecording)
                )
        }
        .buttonStyle(.plain)
        .opacity(isDone ? 0.4 : 1)
        .disabled(isDone || isRecording)
        .accessibilityLabel(isDone ? "All guided views captured" : "Capture guided view \(clipIndex + 1) of 4")
        .accessibilityHint(isDone ? "" : "Tap to capture four representative images")
    }
}

// MARK: - Framing brackets

private struct FramingBrackets: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let s: CGFloat = 36
            let p: CGFloat = 24
            let lw: CGFloat = 3
            let r: CGFloat = 8
            let c = Color(hex: 0xFFD60A)

            // Top-left
            Path { path in
                path.move(to: CGPoint(x: p, y: p + s))
                path.addLine(to: CGPoint(x: p, y: p + r))
                path.addQuadCurve(to: CGPoint(x: p + r, y: p), control: CGPoint(x: p, y: p))
                path.addLine(to: CGPoint(x: p + s, y: p))
            }.stroke(c, lineWidth: lw)

            // Top-right
            Path { path in
                path.move(to: CGPoint(x: w - p - s, y: p))
                path.addLine(to: CGPoint(x: w - p - r, y: p))
                path.addQuadCurve(to: CGPoint(x: w - p, y: p + r), control: CGPoint(x: w - p, y: p))
                path.addLine(to: CGPoint(x: w - p, y: p + s))
            }.stroke(c, lineWidth: lw)

            // Bottom-left
            Path { path in
                path.move(to: CGPoint(x: p, y: h - p - s))
                path.addLine(to: CGPoint(x: p, y: h - p - r))
                path.addQuadCurve(to: CGPoint(x: p + r, y: h - p), control: CGPoint(x: p, y: h - p))
                path.addLine(to: CGPoint(x: p + s, y: h - p))
            }.stroke(c, lineWidth: lw)

            // Bottom-right
            Path { path in
                path.move(to: CGPoint(x: w - p - s, y: h - p))
                path.addLine(to: CGPoint(x: w - p - r, y: h - p))
                path.addQuadCurve(to: CGPoint(x: w - p, y: h - p - r), control: CGPoint(x: w - p, y: h - p))
                path.addLine(to: CGPoint(x: w - p, y: h - p - s))
            }.stroke(c, lineWidth: lw)
        }
    }
}

// MARK: - FlowLayout (chip wrap)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(bounds.size), subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        let totalHeight = y + rowHeight
        return (CGSize(width: maxWidth, height: totalHeight), frames)
    }
}

// MARK: - View helper

private extension View {
    func flexibleFrame(minWidth: CGFloat, maxWidth: CGFloat) -> some View {
        self.frame(minWidth: minWidth, maxWidth: maxWidth)
    }
}

#Preview {
    TeachWizardView(presetName: "Red coffee mug")
        .environmentObject(SSHConnectionManager())
}
