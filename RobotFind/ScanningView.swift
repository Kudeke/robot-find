// ScanningView.swift
// Scanning screen — Sonar bar variant. Spec: README §7.7b

import SwiftUI
import AVFoundation
import CoreHaptics
import Vision

// MARK: - Proximity phase

enum ScanPhase: Equatable {
    case searching, warm, found, lost
    var label: String {
        switch self {
        case .searching: return "Searching…"
        case .warm:      return "Getting warmer…"
        case .found:     return "Found!"
        case .lost:      return "Lost — pan slowly."
        }
    }
}

// MARK: - Scan alert state

enum ScanAlert: Equatable {
    case none
    case timeout
    case covered
    case lowLight
    case batteryWarn
    case batteryCritical
    case multipleMatches
}

// MARK: - Camera + Vision + LiDAR processor (AVCaptureSession-based)

final class ScanProcessor: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureDepthDataOutputDelegate {

    let captureSession = AVCaptureSession()
    private let storedPrints: [VNFeaturePrintObservation]
    private let onResult: (Double, Double, Double) -> Void  // (proximity, direction, distanceMeters)

    private var lastProcessDate = Date.distantPast
    private let minInterval: TimeInterval = 0.15

    private let visionQueue = DispatchQueue(label: "com.fmt.vision", qos: .userInitiated)
    private let depthQueue  = DispatchQueue(label: "com.fmt.depth",  qos: .userInitiated)

    // Latest LiDAR depth map — guarded by depthLock
    private let depthLock = NSLock()
    private var _latestDepthMap: CVPixelBuffer?
    private var latestDepthMap: CVPixelBuffer? {
        get { depthLock.lock(); defer { depthLock.unlock() }; return _latestDepthMap }
        set { depthLock.lock(); defer { depthLock.unlock() }; _latestDepthMap = newValue }
    }

    static var hasLiDAR: Bool {
        AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .depthData, position: .back) != nil
    }

    init(prints: [VNFeaturePrintObservation], onResult: @escaping (Double, Double, Double) -> Void) {
        self.storedPrints = prints
        self.onResult = onResult
    }

    func start(onReady: @escaping () -> Void = {}) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input  = try? AVCaptureDeviceInput(device: device) else { return }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        if captureSession.canAddInput(input) { captureSession.addInput(input) }

        // Video output → Vision processing
        let videoOut = AVCaptureVideoDataOutput()
        videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOut.alwaysDiscardsLateVideoFrames = true
        videoOut.setSampleBufferDelegate(self, queue: visionQueue)
        if captureSession.canAddOutput(videoOut) {
            captureSession.addOutput(videoOut)
            if let conn = videoOut.connection(with: .video), conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
        }

        // Depth output → LiDAR (iPhone 12 Pro+ only)
        if ScanProcessor.hasLiDAR {
            let depthOut = AVCaptureDepthDataOutput()
            depthOut.isFilteringEnabled = true
            depthOut.setDelegate(self, callbackQueue: depthQueue)
            if captureSession.canAddOutput(depthOut) {
                captureSession.addOutput(depthOut)
                // Match depth map orientation to video frame so saliency
                // coordinates map directly to depth map pixel coordinates
                for conn in depthOut.connections {
                    if conn.isVideoOrientationSupported {
                        conn.videoOrientation = .portrait
                    }
                }
            }
        }

        captureSession.commitConfiguration()
        // startRunning is blocking; call onReady after it returns so the
        // preview layer connects to an already-running session (no frozen first frame)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async { onReady() }
        }
    }

    func stop() {
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.stopRunning()
            }
        }
    }

    // MARK: - Video delegate → Vision feature-print matching

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessDate) >= minInterval,
              !storedPrints.isEmpty,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastProcessDate = now

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        let fpRequest       = VNGenerateImageFeaturePrintRequest()
        let saliencyRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
        try? handler.perform([fpRequest, saliencyRequest])

        guard let featurePrint = fpRequest.results?.first as? VNFeaturePrintObservation else { return }

        var minDist: Float = 1.0
        for stored in storedPrints {
            var d: Float = 0
            if (try? featurePrint.computeDistance(&d, to: stored)) != nil {
                minDist = min(minDist, d)
            }
        }

        let proximity = Double(max(0, min(1, 1.0 - Double(minDist))))

        var direction = 0.0
        var depthPoint = CGPoint(x: 0.5, y: 0.5)
        if let saliency = saliencyRequest.results?.first as? VNSaliencyImageObservation,
           let topObj = saliency.salientObjects?.first {
            // Vision y is flipped (0 = bottom); convert to screen coords (0 = top)
            depthPoint = CGPoint(x: topObj.boundingBox.midX,
                                 y: 1.0 - topObj.boundingBox.midY)
            direction = (topObj.boundingBox.midX - 0.5) * 2.0
        }

        // Depth map is now portrait-oriented (matching the video frame), so
        // depthPoint coordinates correspond directly to depth map pixels.
        var distanceMeters = max(0.15, (1.0 - proximity) * 3.0)  // formula fallback
        if let dm = latestDepthMap,
           let measured = Self.sampleDepth(from: dm, at: depthPoint) {
            distanceMeters = Double(measured)
        }

        let (p, d, dist) = (proximity, direction, distanceMeters)
        DispatchQueue.main.async { [weak self] in self?.onResult(p, d, dist) }
    }

    // MARK: - Depth delegate → LiDAR depth map update

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData,
                         timestamp: CMTime, connection: AVCaptureConnection) {
        var data = depthData
        if depthData.depthDataType != kCVPixelFormatType_DepthFloat32 {
            data = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        }
        latestDepthMap = data.depthDataMap
    }

    // MARK: - Depth map sampling

    private static func sampleDepth(from depthMap: CVPixelBuffer, at point: CGPoint) -> Float? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let w   = CVPixelBufferGetWidth(depthMap)
        let h   = CVPixelBufferGetHeight(depthMap)
        let bpr = CVPixelBufferGetBytesPerRow(depthMap)
        let x   = max(0, min(w - 1, Int(point.x * CGFloat(w))))
        let y   = max(0, min(h - 1, Int(point.y * CGFloat(h))))
        let ptr = base.assumingMemoryBound(to: Float32.self)
        let v   = ptr[y * (bpr / MemoryLayout<Float32>.size) + x]
        return (v.isNaN || v <= 0 || v.isInfinite) ? nil : v
    }
}

// MARK: - Scan model (state machine + audio + haptics)

@MainActor
final class ScanModel: ObservableObject {
    @Published var proximity:  Double = 0.15
    @Published var direction:  Double = 0.0
    @Published var phase: ScanPhase = .searching
    @Published var isPaused = false
    @Published var distanceM: Double = 2.5
    @Published var lastNudge: String = ""
    @Published var alert: ScanAlert = .none

    private(set) var item: FMTItem?

    // Simulation
    private var simTimer: Timer?
    private var simT: Double = 0
    private var foundSustainedSince: Date?

    // Timeout (60 s without reaching .warm)
    private var scanStartDate = Date()
    private var reachedWarm = false

    // Covered detection (sustained low proximity > 12 s)
    private var lowProximitySince: Date? = nil

    // Battery
    private var batteryWarnFired = false
    private var batteryCriticalFired = false

    // Camera + Vision + LiDAR
    @Published var hasCameraInput = false
    private var storedPrints: [VNFeaturePrintObservation] = []
    private(set) var scanProcessor: ScanProcessor?

    // Audio
    private var sonarEngine: SonarAudioEngine?
    private let speech = AVSpeechSynthesizer()
    private var lastNudgeDate = Date.distantPast
    private let nudgePhrases = [
        "Move slightly right.", "Move slightly left.",
        "Tilt up.", "Getting warmer.",
        "It\u{2019}s about half a metre ahead.", "Pan slowly.",
    ]
    private var nudgeIndex = 0

    // Haptics
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticAdvancedPatternPlayer?

    func start(item: FMTItem) {
        self.item = item
        storedPrints = FeaturePrintStore.shared.load(for: item.id)
        scanStartDate = Date()
        UIDevice.current.isBatteryMonitoringEnabled = true
        setupCamera()
        sonarEngine = SonarAudioEngine()
        sonarEngine?.start()
        setupHaptics()
        startSimulation()
        UIAccessibility.post(notification: .screenChanged,
                             argument: "Scanning for \(item.name). Pan slowly.")
    }

    private func setupCamera() {
        let proc = ScanProcessor(prints: storedPrints) { [weak self] prox, dir, dist in
            self?.updateFromVision(proximity: prox, direction: dir, distanceMeters: dist)
        }
        scanProcessor = proc
        proc.start { [weak self] in
            self?.hasCameraInput = true   // set AFTER session is running → live preview immediately
        }
    }

    private func updateFromVision(proximity newProx: Double, direction newDir: Double,
                                  distanceMeters: Double) {
        proximity  = newProx
        direction  = newDir
        distanceM = max(0.1, distanceMeters)
    }

    func dismissAlert() {
        alert = .none
        if isPaused { togglePause() }
    }

    func stop() {
        simTimer?.invalidate()
        sonarEngine?.stop()
        try? hapticPlayer?.cancel()
        hapticEngine?.stop(completionHandler: nil)
        scanProcessor?.stop()
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            sonarEngine?.setPaused(true)
            try? hapticPlayer?.cancel()
            UIAccessibility.post(notification: .announcement, argument: "Scanning paused.")
        } else {
            sonarEngine?.setPaused(false)
            updateHapticRate()
            UIAccessibility.post(notification: .announcement, argument: "Scanning resumed.")
        }
    }

    func repeatLastInstruction() {
        let verbosity = UserDefaults.standard.string(forKey: "verbosity") ?? "Standard"
        let msg: String
        if phase == .found, let item {
            msg = verbosity == "Minimal"
                ? "Found."
                : "Found \(item.name). About \(String(format: "%.1f", distanceM)) metres ahead."
        } else {
            msg = directionNudge(verbosity: verbosity)
        }
        speak(msg)
    }

    // MARK: - Simulation loop

    private func startSimulation() {
        simTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard !isPaused, alert == .none else { return }

        // Simulation fallback for seed/untrained items only
        if storedPrints.isEmpty {
            simT += 0.012
            proximity  = max(0, min(1, 0.55 + 0.42 * sin(simT * 0.8)))
            direction  = sin(simT * 0.4) * 0.7
            distanceM = max(0.1, (1 - proximity) * 2.5)
        }
        // else: proximity, direction, distanceM are all set by updateFromVision() (LiDAR)

        // Phase thresholds: lower for real Vision (distance mapping is softer)
        let foundThreshold: Double = storedPrints.isEmpty ? 0.92 : 0.30   // real: dist < 0.70
        let warmThreshold:  Double = storedPrints.isEmpty ? 0.60 : 0.15   // real: dist < 0.85

        let oldPhase = phase
        if proximity > foundThreshold {
            if foundSustainedSince == nil { foundSustainedSince = Date() }
            if let since = foundSustainedSince, Date().timeIntervalSince(since) >= 1.0 {
                phase = .found
            } else {
                phase = .warm
            }
        } else if proximity > warmThreshold {
            foundSustainedSince = nil
            reachedWarm = true
            phase = .warm
        } else {
            foundSustainedSince = nil
            phase = .searching
        }

        // Found event
        if oldPhase != .found && phase == .found { onFound() }

        // ── Error / edge state checks ──────────────────────────────────────

        // 1. Timeout: 60 s without ever reaching warm
        if !reachedWarm && Date().timeIntervalSince(scanStartDate) >= 60 {
            fireAlert(.timeout)
            return
        }

        // 2. Covered: sustained low proximity (< 0.15) for 30 s
        if proximity < 0.15 {
            if lowProximitySince == nil { lowProximitySince = Date() }
            if let since = lowProximitySince,
               Date().timeIntervalSince(since) >= 30, reachedWarm {
                fireAlert(.covered)
                return
            }
        } else {
            lowProximitySince = nil
        }

        // 3. Battery
        let battLevel = Double(UIDevice.current.batteryLevel)
        if battLevel > 0 {                          // -1 = unknown
            if !batteryCriticalFired && battLevel <= 0.05 {
                batteryCriticalFired = true
                fireAlert(.batteryCritical)
                return
            } else if !batteryWarnFired && battLevel <= 0.15 {
                batteryWarnFired = true
                fireAlert(.batteryWarn)
                // Don't return — warning is non-blocking
            }
        }

        // ──────────────────────────────────────────────────────────────────

        sonarEngine?.update(proximity: proximity, direction: direction,
                            enabled: phase != .found)
        updateHapticRate()

        // Spoken nudges — interval and content depend on Verbosity setting
        let verbosity = UserDefaults.standard.string(forKey: "verbosity") ?? "Standard"
        let nudgeInterval: TimeInterval = verbosity == "Minimal" ? 6.0 : 3.0

        if phase != .found && Date().timeIntervalSince(lastNudgeDate) >= nudgeInterval {
            lastNudgeDate = Date()
            let nudge = directionNudge(verbosity: verbosity)
            lastNudge = nudge
            speak(nudge)
        }
    }

    private func fireAlert(_ kind: ScanAlert) {
        sonarEngine?.setPaused(true)
        alert = kind
        if kind == .batteryCritical { isPaused = true }
    }

    private func directionNudge(verbosity: String) -> String {
        let dirWord = abs(direction) < 0.15 ? "center"
                    : direction > 0 ? "right" : "left"
        let distStr = String(format: "%.1f", distanceM)

        switch verbosity {
        case "Minimal":
            if abs(direction) < 0.15 { return "Warmer." }
            return direction > 0 ? "Right." : "Left."

        case "Verbose":
            let itemName = item?.name ?? "item"
            if abs(direction) < 0.15 {
                return "Scanning for \(itemName). Getting warmer — hold steady. About \(distStr) metres ahead."
            }
            return "Scanning for \(itemName). Move \(dirWord). About \(distStr) metres ahead."

        default: // Standard
            if abs(direction) < 0.15 { return "Getting warmer. Hold steady." }
            return direction > 0 ? "Move slightly right." : "Move slightly left."
        }
    }

    private func onFound() {
        guard let item else { return }
        sonarEngine?.setPaused(true)
        let verbosity = UserDefaults.standard.string(forKey: "verbosity") ?? "Standard"
        let msg: String
        let dirPhrase = direction > 0.15 ? "slightly to your right"
                      : direction < -0.15 ? "slightly to your left"
                      : "straight ahead"
        switch verbosity {
        case "Minimal":
            msg = "Found."
        case "Verbose":
            msg = "Found your \(item.name)! It's about \(String(format: "%.1f", distanceM)) metres in front of you, \(dirPhrase). Tap Confirm found."
        default:
            msg = "Found your \(item.name). About \(String(format: "%.1f", distanceM)) metres in front of you, \(dirPhrase)."
        }
        speak(msg)
        playFoundHaptic()
    }

    // MARK: - Speech

    private func speak(_ text: String) {
        guard !UIAccessibility.isVoiceOverRunning else {
            UIAccessibility.post(notification: .announcement, argument: text)
            return
        }
        if speech.isSpeaking { speech.stopSpeaking(at: .word) }
        let utterance = AVSpeechUtterance(string: text)

        // Apply voice from Settings
        let voiceName = UserDefaults.standard.string(forKey: "voice") ?? "Default"
        if voiceName != "Default" {
            utterance.voice = AVSpeechSynthesisVoice.speechVoices().first { $0.name == voiceName }
                ?? AVSpeechSynthesisVoice(language: "en-US")
        }

        // Apply speech rate from Settings
        switch UserDefaults.standard.string(forKey: "speechRate") ?? "Normal" {
        case "Slow": utterance.rate = 0.35
        case "Fast": utterance.rate = 0.60
        default:     utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        }

        speech.speak(utterance)
    }

    // MARK: - Haptics

    private func setupHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        hapticEngine = try? CHHapticEngine()
        try? hapticEngine?.start()
        hapticEngine?.resetHandler = { [weak self] in
            try? self?.hapticEngine?.start()
        }
    }

    private func updateHapticRate() {
        // Haptic pulses are triggered alongside sonar pings in playFoundHaptic().
        // Continuous proximity haptic requires CHHapticAdvancedPatternPlayer;
        // left as a future enhancement once the real Vision pipeline is wired up.
    }

    private func playFoundHaptic() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }
}

// MARK: - Sonar audio engine (AVAudioPlayer-based, no AVAudioEngine)

final class SonarAudioEngine {
    private var pingTimer: Timer?
    private var paused = false
    private var currentProximity: Double = 0.1
    private var currentDirection: Double = 0.0
    private var enabled = true
    // Retain active players until playback finishes
    private var activePlayers: [AVAudioPlayer] = []

    func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                         options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        schedulePingTimer()
    }

    func stop() {
        pingTimer?.invalidate()
        activePlayers.forEach { $0.stop() }
        activePlayers.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }

    func setPaused(_ pause: Bool) {
        paused = pause
        if pause {
            activePlayers.forEach { $0.stop() }
            activePlayers.removeAll()
        }
    }

    func update(proximity: Double, direction: Double, enabled: Bool) {
        currentProximity = proximity
        currentDirection = direction
        self.enabled = enabled
    }

    // MARK: Private

    private func schedulePingTimer() {
        pingTimer?.invalidate()
        firePing()
    }

    private func firePing() {
        guard enabled && !paused else { scheduleNext(); return }
        playPing(proximity: currentProximity, direction: currentDirection)
        scheduleNext()
    }

    private func scheduleNext() {
        let rate = 0.5 + currentProximity * 7.5        // 0.5–8 Hz
        let interval = max(0.125, 1.0 / rate)
        pingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.firePing()
        }
    }

    private func playPing(proximity: Double, direction: Double) {
        let frequency = 440.0 + proximity * 800.0      // 440–1240 Hz
        guard let wavData = buildWAV(frequency: frequency) else { return }
        guard let player = try? AVAudioPlayer(data: wavData) else { return }
        player.pan    = Float(max(-1, min(1, direction)))
        player.volume = 0.6
        player.prepareToPlay()
        player.play()
        activePlayers.append(player)
        // Release after ping duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.activePlayers.removeAll { $0 === player }
        }
    }

    // Build a mono 16-bit WAV buffer with shaped sine wave (12ms attack, 120ms decay)
    private func buildWAV(frequency: Double) -> Data? {
        let sampleRate = 44100
        let numSamples = Int(Double(sampleRate) * 0.14)   // 140ms total
        let attackN    = sampleRate * 12 / 1000            // 12ms
        let decayN     = sampleRate * 120 / 1000           // 120ms

        var samples = [Int16](repeating: 0, count: numSamples)
        for i in 0..<numSamples {
            let t        = Double(i) / Double(sampleRate)
            let raw      = sin(2.0 * .pi * frequency * t)
            let envelope: Double
            if i < attackN {
                envelope = Double(i) / Double(attackN)
            } else if i < attackN + decayN {
                let d = Double(i - attackN) / Double(decayN)
                envelope = pow(1.0 - d, 2)
            } else {
                envelope = 0
            }
            samples[i] = Int16(raw * envelope * Double(Int16.max))
        }

        let dataBytes = numSamples * 2
        var wav = Data()

        func u32le(_ v: UInt32) -> [UInt8] {
            var x = v.littleEndian
            return withUnsafeBytes(of: &x) { Array($0) }
        }
        func u16le(_ v: UInt16) -> [UInt8] {
            var x = v.littleEndian
            return withUnsafeBytes(of: &x) { Array($0) }
        }

        wav.append(contentsOf: "RIFF".utf8)
        wav.append(contentsOf: u32le(UInt32(36 + dataBytes)))
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(contentsOf: u32le(16))
        wav.append(contentsOf: u16le(1))                          // PCM
        wav.append(contentsOf: u16le(1))                          // mono
        wav.append(contentsOf: u32le(UInt32(sampleRate)))
        wav.append(contentsOf: u32le(UInt32(sampleRate * 2)))     // byte rate
        wav.append(contentsOf: u16le(2))                          // block align
        wav.append(contentsOf: u16le(16))                         // bits per sample
        wav.append(contentsOf: "data".utf8)
        wav.append(contentsOf: u32le(UInt32(dataBytes)))
        samples.withUnsafeBytes { wav.append(contentsOf: $0) }
        return wav
    }
}

// MARK: - ScanningView

struct ScanningView: View {
    let item: FMTItem
    var onFound: () -> Void = {}
    var onCancel: () -> Void = {}

    @StateObject private var model = ScanModel()
    @State private var cameraPermissionDenied = false

    var body: some View {
        Group {
            if cameraPermissionDenied {
                RecoveryView(
                    systemImage: "camera.fill",
                    title: "Camera access needed",
                    message: "RobotFind needs camera access to find your items. Open Settings to allow it.",
                    primaryLabel: "Open Settings",
                    primaryAction: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    },
                    secondaryLabel: "Cancel",
                    secondaryAction: onCancel
                )
            } else {
                scanningBody
            }
        }
        .onAppear {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                model.start(item: item)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        if granted { model.start(item: item) }
                        else { cameraPermissionDenied = true }
                    }
                }
            default:
                cameraPermissionDenied = true
            }
        }
        .onDisappear { model.stop() }
    }

    private var scanningBody: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            // Real camera preview on device; gradient mock on Simulator
            if model.hasCameraInput, let proc = model.scanProcessor {
                CameraPreviewView(session: proc.captureSession)
                    .ignoresSafeArea()
            } else {
                mockCameraFeed
                mockTarget
                if model.phase != .searching { boundingBox }
            }

            reticle.frame(maxWidth: .infinity, maxHeight: .infinity)
            scanHeader

            VStack {
                Spacer()
                bottomHUD
            }

            // Error overlay
            if model.alert != .none {
                Color.black.opacity(0.5).ignoresSafeArea()
                alertOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onTapGesture(count: 1) {
            if model.alert != .none { model.dismissAlert() }
            else { model.repeatLastInstruction() }
        }
        .accessibilityAction(.magicTap) { model.togglePause() }
        .gesture(
            DragGesture(minimumDistance: 60)
                .onEnded { val in
                    if val.translation.height > 60 && abs(val.translation.width) < 100 {
                        onCancel()
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scanning for \(item.name). \(model.phase.label)")
        .accessibilityValue(hudAccessibilityValue)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityAction(named: "Repeat") { model.repeatLastInstruction() }
        .accessibilityAction(named: "Pause")  { model.togglePause() }
        .accessibilityAction(named: "Stop")   { onCancel() }
    }

    // MARK: - Alert overlay

    @ViewBuilder
    private var alertOverlay: some View {
        VStack {
            Spacer()
            switch model.alert {
            case .none: EmptyView()
            case .timeout:
                ScanningAlertOverlay(kind: .timeout(itemName: item.name)) {
                    model.dismissAlert()         // Try another room
                } onSecondary: {
                    onCancel()                   // Re-train → go back
                }
            case .covered:
                ScanningAlertOverlay(kind: .covered) {
                    model.dismissAlert()
                }
            case .lowLight:
                ScanningAlertOverlay(kind: .lowLight) {
                    // TODO: toggle flashlight via AVCaptureDevice.torchMode
                    model.dismissAlert()
                }
            case .batteryWarn:
                ScanningAlertOverlay(kind: .batteryWarn) {
                    model.dismissAlert()
                } onSecondary: {
                    onCancel()
                }
            case .batteryCritical:
                ScanningAlertOverlay(kind: .batteryCritical) {
                    onCancel()
                }
            case .multipleMatches:
                ScanningAlertOverlay(kind: .multipleMatches) {
                    model.dismissAlert()         // Closer one
                } onSecondary: {
                    model.dismissAlert()         // Farther one
                }
            }
            Spacer().frame(height: 40)
        }
    }

    // MARK: - Mock camera feed

    private var mockCameraFeed: some View {
        RadialGradient(
            colors: [Color(hex: 0x3a3a40), Color(hex: 0x08080a)],
            center: UnitPoint(
                x: 0.5 + model.direction * 0.3,
                y: 0.4 - model.proximity * 0.1
            ),
            startRadius: 0,
            endRadius: 400
        )
        .ignoresSafeArea()
        .animation(.linear(duration: 0.1), value: model.direction)
        .animation(.linear(duration: 0.1), value: model.proximity)
    }

    // MARK: - Mock target

    private var mockTarget: some View {
        let (colorA, colorB) = item.kind.swatch
        let scale = 0.6 + model.proximity * 0.6
        let xOffset = model.direction * 80

        return RoundedRectangle(cornerRadius: 26)
            .fill(LinearGradient(colors: [colorA, colorB],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 110, height: 110)
            .opacity(0.3 + model.proximity * 0.7)
            .scaleEffect(scale)
            .offset(x: xOffset, y: -60)
            .shadow(color: model.phase == .found
                    ? Color(hex: 0xFFD60A).opacity(0.5) : .clear,
                    radius: 30)
            .animation(.linear(duration: 0.1), value: model.proximity)
            .animation(.linear(duration: 0.1), value: model.direction)
    }

    // MARK: - Bounding box

    private var boundingBox: some View {
        let scale = 0.6 + model.proximity * 0.6
        let xOffset = model.direction * 80
        let isFound = model.phase == .found

        return RoundedRectangle(cornerRadius: 16)
            .strokeBorder(isFound ? Color(hex: 0xFFD60A) : Color(hex: 0xFFD60A).opacity(0.6),
                          lineWidth: 4)
            .frame(width: 150, height: 150)
            .scaleEffect(scale)
            .offset(x: xOffset, y: -60)
            .shadow(color: isFound ? Color(hex: 0xFFD60A).opacity(0.5) : .clear, radius: 20)
            .animation(.linear(duration: 0.1), value: model.proximity)
            .animation(.linear(duration: 0.1), value: model.direction)
    }

    // MARK: - Crosshair reticle

    private var reticle: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let r: CGFloat = 34
            let arm: CGFloat = 12

            // Dashed ring
            var ring = Path()
            ring.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            ctx.stroke(ring, with: .color(.white.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 2, dash: [4, 6]))

            // Crosshair arms
            let arms: [(CGPoint, CGPoint)] = [
                (CGPoint(x: cx, y: cy - r - arm), CGPoint(x: cx, y: cy - r)),
                (CGPoint(x: cx, y: cy + r),       CGPoint(x: cx, y: cy + r + arm)),
                (CGPoint(x: cx - r - arm, y: cy), CGPoint(x: cx - r, y: cy)),
                (CGPoint(x: cx + r, y: cy),       CGPoint(x: cx + r + arm, y: cy)),
            ]
            for (a, b) in arms {
                var p = Path()
                p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(.white.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Top header

    private var scanHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LOOKING FOR")
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(item.name)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.black.opacity(0.6))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 2))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Stop scanning")
            .accessibilityHint("Exits scanning")
        }
        .padding(.horizontal, 16)
        .padding(.top, 60)
        .padding(.bottom, 14)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.7), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: - Bottom HUD

    private var bottomHUD: some View {
        VStack(spacing: 0) {
            // Caption strip
            captionStrip

            // Proximity bar
            proximityBar
                .padding(.top, 20)

            // Direction indicator
            directionIndicator
                .padding(.top, 14)

            // Confirm found button
            if model.phase == .found {
                confirmFoundButton
                    .padding(.top, 16)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
        .padding(.top, 24)
        .background(
            LinearGradient(colors: [.clear, Color.black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var captionStrip: some View {
        let dirLabel = abs(model.direction) < 0.15 ? "Hold steady"
                     : model.direction > 0 ? "Pan right" : "Pan left"
        let text = model.phase == .found
            ? "Found! About \(String(format: "%.1f", model.distanceM)) m ahead"
            : "\(dirLabel) • \(String(format: "%.1f", model.distanceM)) m"

        return Text(text)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 18)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel(text)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var proximityBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Cold").frame(maxWidth: .infinity, alignment: .leading)
                Text("Getting warmer").frame(maxWidth: .infinity, alignment: .center)
                Text("Hot").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 13, weight: .semibold))
            .kerning(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Color.white.opacity(0.7))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.15))
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color(hex: 0x4D8BFF), location: 0),
                                    .init(color: Color(hex: 0xFFD60A), location: 0.5),
                                    .init(color: Color(hex: 0xFF453A), location: 0.9),
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * model.proximity)
                        .animation(.linear(duration: 0.1), value: model.proximity)
                }
            }
            .frame(height: 14)
            .accessibilityLabel("Proximity \(Int(model.proximity * 100)) percent")
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var directionIndicator: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let midX = w / 2
            let arrowX = midX + model.direction * w * 0.4

            ZStack(alignment: .leading) {
                // Centre line
                Rectangle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 4, height: 36)
                    .offset(x: midX - 2)

                // Triangle arrow
                Canvas { ctx, size in
                    var path = Path()
                    path.move(to: CGPoint(x: arrowX, y: 0))
                    path.addLine(to: CGPoint(x: arrowX - 14, y: 36))
                    path.addLine(to: CGPoint(x: arrowX + 14, y: 36))
                    path.closeSubpath()
                    ctx.fill(path, with: .color(Color(hex: 0xFFD60A)))
                    ctx.stroke(path, with: .color(.black.opacity(0.4)),
                               style: StrokeStyle(lineWidth: 1.5))
                }
                .animation(.linear(duration: 0.1), value: model.direction)
            }
        }
        .frame(height: 36)
        .accessibilityHidden(true)
    }

    private var confirmFoundButton: some View {
        Button(action: onFound) {
            Text("Confirm found")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Color(hex: 0xFFD60A))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Confirm found")
        .accessibilityHint("Confirms the item is found")
    }

    // MARK: - Accessibility value

    private var hudAccessibilityValue: String {
        let dir = abs(model.direction) < 0.15 ? "ahead"
                : model.direction > 0 ? "to the right" : "to the left"
        return "\(String(format: "%.1f", model.distanceM)) metres \(dir). \(Int(model.proximity * 100)) percent confidence."
    }
}

// MARK: - Camera preview (AVCaptureVideoPreviewLayer)

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
            // Disable implicit animation so the layer frame tracks bounds without lag
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}

#Preview {
    ScanningView(item: FMTItem.seed[0])
}
