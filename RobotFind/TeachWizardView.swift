// TeachWizardView.swift
// Teach wizard — 5 steps with four guided image-capture views.

import SwiftUI
import ARKit
import SceneKit
import UIKit

// MARK: - Teach camera model (camera preview + guided capture)

final class TeachCameraModel: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    @Published var hasCameraInput = false
    @Published private(set) var distanceProgress: Double = 0
    @Published private(set) var guidanceText = "Center the item to begin guided capture."

    private let sessionQueue = DispatchQueue(label: "com.fmt.teach", qos: .userInitiated)
    private let targetDistance: Float = 0.45
    private let minimumDistance: Float = 0.25
    private let maximumDistance: Float = 0.85
    private var teachingAnchor: ARAnchor?
    private var captureStartedAt: Date?
    private var sampleTargets: [Double] = []
    private var sampledTargets = Set<Double>()
    private var sampleHandler: ((CVPixelBuffer) throws -> Void)?
    private var captureCompletion: ((Result<Int, Error>) -> Void)?
    private var captureWorkItem: DispatchWorkItem?

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
                 sampleHandler: @escaping (CVPixelBuffer) throws -> Void,
                 completion: @escaping (Result<Int, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureWorkItem?.cancel()
            self.captureStartedAt = Date()
            self.sampleTargets = [0.15, 0.4, 0.65, 0.9]
            self.sampledTargets.removeAll()
            self.sampleHandler = sampleHandler
            self.captureCompletion = completion
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.captureStartedAt != nil else { return }
                let count = self.sampledTargets.count
                self.captureStartedAt = nil
                self.sampleHandler = nil
                let completion = self.captureCompletion
                self.captureCompletion = nil
                DispatchQueue.main.async { completion?(.success(count)) }
            }
            self.captureWorkItem = workItem
            self.sessionQueue.asyncAfter(deadline: .now() + duration, execute: workItem)
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if teachingAnchor == nil {
            placeTeachingAnchor(from: frame)
        }
        let distanceIsGood = updateDistanceGuidance(from: frame)

        guard let startedAt = captureStartedAt,
              let sampleHandler,
              let target = sampleTargets.first(where: { !sampledTargets.contains($0) }),
              distanceIsGood,
              Date().timeIntervalSince(startedAt) / 1.8 >= target else { return }
        do {
            try sampleHandler(frame.capturedImage)
            sampledTargets.insert(target)
        } catch {
            captureWorkItem?.cancel()
            captureStartedAt = nil
            self.sampleHandler = nil
            let completion = captureCompletion
            captureCompletion = nil
            DispatchQueue.main.async { completion?(.failure(error)) }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            if let anchor = self?.teachingAnchor {
                self?.session.remove(anchor: anchor)
            }
            self?.teachingAnchor = nil
            self?.captureWorkItem?.cancel()
            self?.captureStartedAt = nil
            self?.sampleHandler = nil
            self?.captureCompletion = nil
            DispatchQueue.main.async {
                self?.distanceProgress = 0
                self?.guidanceText = "Center the item to begin guided capture."
            }
            self?.session.pause()
        }
    }

    private func placeTeachingAnchor(from frame: ARFrame) {
        var transform = frame.camera.transform
        let forwardOffset = SIMD4<Float>(0, 0, -0.55, 0)
        transform.columns.3 += transform * forwardOffset

        let query = ARRaycastQuery(
            origin: frame.camera.transform.translation,
            direction: -frame.camera.transform.forward,
            allowing: .estimatedPlane,
            alignment: .horizontal
        )
        if let result = session.raycast(query).first {
            transform = result.worldTransform
        }

        let anchor = ARAnchor(name: "RobotFindTeachingAnchor", transform: transform)
        teachingAnchor = anchor
        session.add(anchor: anchor)
        print("[TeachCapture] AR teaching anchor placed")
    }

    private func updateDistanceGuidance(from frame: ARFrame) -> Bool {
        guard let anchor = teachingAnchor else { return false }
        let cameraPosition = frame.camera.transform.translation
        let anchorPosition = anchor.transform.translation
        let distance = simd_distance(cameraPosition, anchorPosition)
        let progress = max(0, 1 - abs(distance - targetDistance) / (maximumDistance - minimumDistance))
        let clampedProgress = min(1, progress)
        let text: String
        if distance < minimumDistance {
            text = "Move slightly farther from the item."
        } else if distance > maximumDistance {
            text = "Move closer to the item."
        } else if clampedProgress < 0.7 {
            text = "Hold the phone about one foot away."
        } else if captureStartedAt != nil {
            text = "Good distance. Move slowly around the item."
        } else {
            text = "Good distance. Tap capture when ready."
        }

        DispatchQueue.main.async { [weak self] in
            self?.distanceProgress = Double(clampedProgress)
            self?.guidanceText = text
        }
        return clampedProgress >= 0.7
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
}

struct TeachWizardView: View {
    var presetName: String = ""
    var onCancel: () -> Void = {}
    var onComplete: (TeachResult) -> Void = { _ in }

    @State private var step = 1
    @State private var itemName = ""
    @State private var clipsRecorded = 0
    @State private var isRecording = false
    @State private var trainProgress: Double = 0
    @State private var trainFailed = false
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
                let stepNames = ["", "Name your item", "Tips for capture", "Capture guided views", "Preparing item", "Done"]
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
        "Each guided view takes about 2 seconds.",
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

                // Prepare / Next
                Button {
                    if allDone {
                        trainProgress = 0
                        step = 4
                        startPreparingItem()
                    }
                } label: {
                    Text(allDone ? "Prepare item" : "Next")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(allDone ? FMTTheme.onAccent : FMTTheme.onAccent.opacity(0.45))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(allDone ? FMTTheme.accent : FMTTheme.accent.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
                }
                .disabled(!allDone)
                .accessibilityLabel(allDone ? "Prepare item" : "Next")
                .accessibilityHint(allDone
                    ? "Prepares this item, step 4 of 5"
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
        let done = trainProgress >= 100

        return VStack(spacing: 0) {
            Spacer()

            if trainFailed {
                // ── Preparation failure state ───────────────────────────
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
                            .tracking(-0.4)
                            .foregroundStyle(FMTTheme.text)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)

                        Text("I wasn\u{2019}t able to complete the capture for your \(itemName.isEmpty ? "item" : itemName) this time. Let\u{2019}s try the guided views again.")
                            .font(.system(size: 17))
                            .foregroundStyle(FMTTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                }
                .padding(.horizontal, 28)

                Spacer()

                bottomButton(
                    label: "Retry guided views",
                    hint: "Goes back to the guided capture step",
                    systemImage: "arrow.counterclockwise",
                    enabled: true
                ) {
                    trainFailed = false
                    clipsRecorded = 0
                    step = 3
                }

            } else {
                // ── Normal progress ring ────────────────────────────────
                VStack(spacing: 28) {
                    ZStack {
                        Circle()
                            .stroke(FMTTheme.separator, lineWidth: 10)
                            .frame(width: 200, height: 200)

                        Circle()
                            .trim(from: 0, to: trainProgress / 100)
                            .stroke(done ? FMTTheme.success : FMTTheme.accent,
                                    style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .frame(width: 200, height: 200)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.2), value: trainProgress)

                        if done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 56, weight: .bold))
                                .foregroundStyle(FMTTheme.success)
                        } else {
                            Text("\(Int(trainProgress))%")
                                .font(.system(size: 56, weight: .bold))
                                .tracking(-1.5)
                                .foregroundStyle(FMTTheme.text)
                        }
                    }
                    .accessibilityLabel("Preparing item, \(Int(trainProgress)) percent complete")
                    .accessibilityAddTraits(.updatesFrequently)

                    VStack(spacing: 10) {
                        Text(done ? "Capture complete" : "Preparing item\u{2026}")
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.4)
                            .foregroundStyle(FMTTheme.text)
                            .accessibilityAddTraits(.isHeader)

                        Text(done
                             ? "Your \(itemName.isEmpty ? "item" : itemName) is saved for the next search flow."
                             : "Checking the guided capture for your \(itemName.isEmpty ? "item" : itemName). This will take just a few seconds.")
                            .font(.system(size: 19))
                            .foregroundStyle(FMTTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                }
                .padding(.horizontal, 28)

                Spacer()

                bottomButton(
                    label: "Continue",
                    hint: "Goes to the final step",
                    enabled: done
                ) { step = 5 }
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
                    onComplete(TeachResult(itemID: itemID, name: itemName.isEmpty ? "New item" : itemName, tryFind: true))
                }

                Button {
                    onComplete(TeachResult(itemID: itemID, name: itemName.isEmpty ? "New item" : itemName, tryFind: false))
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
        teachCamera.capture(duration: 1.8, sampleHandler: { pixelBuffer in
            try TeachCaptureStore.shared.appendJPEG(from: pixelBuffer, itemID: itemID)
        }) { result in
            isRecording = false
            switch result {
            case .success(let samples):
                clipsRecorded = min(4, clipsRecorded + 1)
                let remaining = 4 - clipsRecorded
                print("[TeachCapture] capture \(clipsRecorded) completed, samples=\(samples)")
                let msg = remaining > 0
                    ? "\(clipsRecorded) of 4 captured. \(remaining) remaining."
                    : "All 4 guided views captured. Tap Prepare item."
                UIAccessibility.post(notification: .announcement, argument: msg)
            case .failure(let error):
                trainFailed = true
                print("[TeachCapture] capture failed: \(error.localizedDescription)")
                UIAccessibility.post(notification: .announcement,
                                     argument: "The image could not be saved. Please try this view again.")
            }
        }
    }

    private func beginCaptureSession() {
        do {
            try TeachCaptureStore.shared.startSession(itemID: itemID)
            trainFailed = false
        } catch {
            trainFailed = true
            print("[TeachCapture] session failed: \(error.localizedDescription)")
            UIAccessibility.post(notification: .announcement,
                                 argument: "The capture folder could not be prepared. Please try again.")
        }
    }

    private func startPreparingItem() {
        trainProgress = 0

        guard clipsRecorded >= 4 else {
            trainFailed = true
            UIAccessibility.post(notification: .announcement,
                                 argument: "Capture incomplete. Tap Retry guided views to try again.")
            return
        }

        do {
            let imageCount = try TeachCaptureStore.shared.imageCount(itemID: itemID)
            guard imageCount >= 8 else {
                throw TeachCaptureError.insufficientImages(imageCount)
            }
            print("[TeachCapture] teaching completed, totalImages=\(imageCount)")
        } catch {
            trainFailed = true
            print("[TeachCapture] teaching failed: \(error.localizedDescription)")
            UIAccessibility.post(notification: .announcement,
                                 argument: "Too few usable images were captured. Tap Retry guided views to try again.")
            return
        }

        func tick() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                guard trainProgress < 100 else { return }
                trainProgress = min(100, trainProgress + 5)
                let pct = Int(trainProgress)
                if [25, 50, 75, 100].contains(pct) {
                    UIAccessibility.post(notification: .announcement,
                                         argument: "Preparing item \(pct) percent complete.")
                }
                tick()
            }
        }
        tick()
    }
}

// MARK: - Camera preview (UIViewRepresentable)

private struct CameraPreviewView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> PreviewUIView { PreviewUIView(session: session) }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        private let sceneView: ARSCNView

        init(session: ARSession) {
            sceneView = ARSCNView(frame: .zero, options: nil)
            super.init(frame: .zero)
            sceneView.session = session
            sceneView.scene = SCNScene()
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
}
