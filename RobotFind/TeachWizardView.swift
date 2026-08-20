// TeachWizardView.swift
// Teach wizard — 5 steps. Spec: README §7.6

import SwiftUI
import AVFoundation
import Vision

// MARK: - Teach camera model (camera preview + feature print capture)

final class TeachCameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var hasCameraInput = false

    private let captureQueue = DispatchQueue(label: "com.fmt.teach", qos: .userInitiated)
    private var capturing = false
    private var captureEndDate = Date.distantPast
    private var collectedBuffers: [CMSampleBuffer] = []
    private var frameCounter = 0
    private var completionHandler: (([VNFeaturePrintObservation]) -> Void)?

    func setup() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .medium
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
            if let conn = output.connection(with: .video), conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
        }
        session.commitConfiguration()
        captureQueue.async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async { self?.hasCameraInput = true }
        }
    }

    // Call from main thread; completion called on main thread
    func capture(duration: TimeInterval, completion: @escaping ([VNFeaturePrintObservation]) -> Void) {
        captureQueue.async { [weak self] in
            guard let self else { return }
            self.collectedBuffers.removeAll()
            self.frameCounter = 0
            self.captureEndDate = Date().addingTimeInterval(duration)
            self.completionHandler = { prints in DispatchQueue.main.async { completion(prints) } }
            self.capturing = true
        }
    }

    func stop() {
        captureQueue.async { [weak self] in self?.session.stopRunning() }
    }

    // Runs on captureQueue (serial) — no concurrent access issues
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard capturing else { return }
        frameCounter += 1

        // Collect ~1 frame per 0.3 s (every 9th frame at 30 fps → 6 frames per 1.8 s clip)
        if frameCounter % 9 == 0, Date() < captureEndDate {
            collectedBuffers.append(sampleBuffer)
        }

        guard Date() >= captureEndDate else { return }
        capturing = false
        let buffers = collectedBuffers
        collectedBuffers.removeAll()
        let done = completionHandler
        completionHandler = nil

        // Extract feature prints synchronously on this queue, then deliver
        var prints: [VNFeaturePrintObservation] = []
        for buf in buffers {
            guard let px = CMSampleBufferGetImageBuffer(buf) else { continue }
            let req = VNGenerateImageFeaturePrintRequest()
            try? VNImageRequestHandler(cvPixelBuffer: px, options: [:]).perform([req])
            if let obs = req.results?.first as? VNFeaturePrintObservation {
                prints.append(obs)
            }
        }
        done?(prints)
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

    // Vision / camera
    @State private var itemID = UUID().uuidString
    @StateObject private var teachCamera = TeachCameraModel()
    @State private var collectedPrints: [VNFeaturePrintObservation] = []

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
                let stepNames = ["", "Name your item", "Tips for recording", "Record videos", "Training", "Done"]
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
        "You\u{2019}ll record 4 short videos from different angles.",
        "Each video is about 5 seconds.",
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
                             hint: "Starts video recording, step 3 of 5",
                             enabled: true) {
                    clipsRecorded = 0
                    step = 3
                }
                Button {
                    clipsRecorded = 0
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

    // MARK: ─ Step 3: Record 4 clips ──────────────────────────────────────

    private var step3: some View {
        let currentAngle = angles[min(clipsRecorded, 3)]
        let allDone = clipsRecorded >= 4

        return VStack(spacing: 0) {
            // Angle label
            VStack(spacing: 6) {
                Text("Video \(min(clipsRecorded + 1, 4)) of 4")
                    .font(.system(size: 14, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(allDone ? "All 4 videos recorded" : currentAngle)
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
            .accessibilityLabel("\(clipsRecorded) of 4 videos recorded")

            // Record button + status + Next
            VStack(spacing: 14) {
                RecordButton(isRecording: isRecording, isDone: allDone, clipIndex: clipsRecorded) {
                    guard !isRecording && !allDone else { return }
                    startRecording()
                }

                Text(allDone ? "Tap Next to train the model"
                     : (isRecording ? "Recording\u{2026}" : "Tap to record"))
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .accessibilityAddTraits(.updatesFrequently)

                // Train now / Next
                Button {
                    if allDone {
                        trainProgress = 0
                        step = 4
                        startTraining()
                    }
                } label: {
                    Text(allDone ? "Train now" : "Next")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(allDone ? FMTTheme.onAccent : FMTTheme.onAccent.opacity(0.45))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(allDone ? FMTTheme.accent : FMTTheme.accent.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
                }
                .disabled(!allDone)
                .accessibilityLabel(allDone ? "Train now" : "Next")
                .accessibilityHint(allDone
                    ? "Trains the model on your videos, step 4 of 5"
                    : "Continues to training when all 4 clips are recorded")
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

            // Coaching caption
            Text(isRecording ? "Good, keep going. Move slowly." : "Hold the phone about one foot away.")
                .font(.system(size: 15))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityLabel(isRecording
                    ? "Live coaching: Good, keep going"
                    : "Live coaching: Hold the phone about one foot away")
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.75, contentMode: .fit)
    }

    // MARK: ─ Step 4: Training ─────────────────────────────────────────────

    private var step4: some View {
        let done = trainProgress >= 100

        return VStack(spacing: 0) {
            Spacer()

            if trainFailed {
                // ── Training failure state ──────────────────────────────
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

                        Text("I wasn\u{2019}t able to learn your \(itemName.isEmpty ? "item" : itemName) this time. Let\u{2019}s try recording the videos again.")
                            .font(.system(size: 17))
                            .foregroundStyle(FMTTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                }
                .padding(.horizontal, 28)

                Spacer()

                bottomButton(
                    label: "Re-record videos",
                    hint: "Goes back to recording step",
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
                    .accessibilityLabel("Training, \(Int(trainProgress)) percent complete")
                    .accessibilityAddTraits(.updatesFrequently)

                    VStack(spacing: 10) {
                        Text(done ? "Done!" : "Teaching me\u{2026}")
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.4)
                            .foregroundStyle(FMTTheme.text)
                            .accessibilityAddTraits(.isHeader)

                        Text(done
                             ? "I learned your \(itemName.isEmpty ? "item" : itemName)."
                             : "Teaching me about your \(itemName.isEmpty ? "item" : itemName). This will take just a few seconds.")
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
                     + Text(". Want to try it?"))
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
                    hint: "Goes to scanning with this item selected",
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
        UIAccessibility.post(notification: .announcement, argument: "Recording started.")
        teachCamera.capture(duration: 1.8) { prints in
            collectedPrints.append(contentsOf: prints)
            isRecording = false
            clipsRecorded = min(4, clipsRecorded + 1)
            let remaining = 4 - clipsRecorded
            let msg = remaining > 0
                ? "\(clipsRecorded) of 4 recorded. \(remaining) remaining."
                : "All 4 videos recorded. Tap Train now."
            UIAccessibility.post(notification: .announcement, argument: msg)
        }
    }

    private func startTraining() {
        trainProgress = 0

        guard !collectedPrints.isEmpty else {
            trainFailed = true
            UIAccessibility.post(notification: .announcement,
                                 argument: "Training failed. Tap Re-record videos to try again.")
            return
        }

        // Persist feature prints keyed by this item's ID
        FeaturePrintStore.shared.save(collectedPrints, for: itemID)

        // Animate progress to 100 % (actual work is already done above)
        func tick() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                guard trainProgress < 100 else { return }
                trainProgress = min(100, trainProgress + 5)
                let pct = Int(trainProgress)
                if [25, 50, 75, 100].contains(pct) {
                    UIAccessibility.post(notification: .announcement,
                                         argument: "Training \(pct) percent complete.")
                }
                tick()
            }
        }
        tick()
    }
}

// MARK: - Camera preview (UIViewRepresentable)

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView { PreviewUIView(session: session) }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        private let previewLayer: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            super.init(frame: .zero)
            layer.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}

// MARK: - Record button

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
        .accessibilityLabel(isDone ? "All videos recorded" : "Record video \(clipIndex + 1) of 4")
        .accessibilityHint(isDone ? "" : "Tap to record")
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
