// OnboardingView.swift
// Splash → Permissions (camera, mic) → Onboarding 3 slides
// Spec: README §7.1 + §7.2

import SwiftUI
import AVFoundation

// MARK: - Entry coordinator

struct AppEntryView: View {
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var permissionsDone = false

    var body: some View {
        if onboardingDone {
            HomeView()
        } else if permissionsDone {
            OnboardingView { onboardingDone = true }
                .transition(.opacity)
        } else {
            PermissionsFlow { permissionsDone = true }
                .transition(.opacity)
        }
    }
}

// MARK: - Permissions flow

private enum PermStep { case camera, mic, done }

struct PermissionsFlow: View {
    var onDone: () -> Void

    @State private var step: PermStep = .camera

    var body: some View {
        switch step {
        case .camera:
            PermissionScreen(
                systemImage: "camera.fill",
                title: "Camera access",
                rationale: "RobotFind uses the camera to recognise your objects and guide you to them.",
                whyText: "The camera feed never leaves your device. It is only processed on-chip by the AI model.",
                allowLabel: "Allow Camera"
            ) {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    DispatchQueue.main.async { step = .mic }
                }
            } onDeny: {
                step = .mic
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

        case .mic:
            PermissionScreen(
                systemImage: "mic.fill",
                title: "Microphone access",
                rationale: "The microphone lets you dictate item names and enables voice-guided teaching.",
                whyText: "Audio is never recorded or stored. It is only used live for voice input.",
                allowLabel: "Allow Microphone"
            ) {
                AVAudioSession.sharedInstance().requestRecordPermission { _ in
                    DispatchQueue.main.async { step = .done }
                }
            } onDeny: {
                step = .done
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

        case .done:
            Color.clear.onAppear { onDone() }
        }
    }
}

// MARK: - Single permission screen

private struct PermissionScreen: View {
    let systemImage: String
    let title: String
    let rationale: String
    let whyText: String
    let allowLabel: String
    var onAllow: () -> Void
    var onDeny: () -> Void

    @State private var showWhy = false
    @State private var deniedAndShowingRecovery = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Icon
                Circle()
                    .fill(FMTTheme.chipBg)
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(FMTTheme.accent)
                    )
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(FMTTheme.text)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text(rationale)
                        .font(.system(size: 19))
                        .foregroundStyle(FMTTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
            .padding(.horizontal, 32)

            // "Why we need this" disclosure
            DisclosureGroup(isExpanded: $showWhy) {
                Text(whyText)
                    .font(.system(size: 15))
                    .foregroundStyle(FMTTheme.textSecondary)
                    .padding(.top, 8)
            } label: {
                Text("Why we need this")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FMTTheme.accent)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .accessibilityLabel("Why we need \(title)")

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button {
                    checkAndAllow()
                } label: {
                    Text(allowLabel)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(FMTTheme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(FMTTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(allowLabel)
                .accessibilityHint("Requests permission and continues")

                Button(action: onDeny) {
                    Text("Not now")
                        .font(.system(size: 17))
                        .foregroundStyle(FMTTheme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Not now")
                .accessibilityHint("Skips this permission. Some features may be limited.")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
        .background(FMTTheme.background)
        .onAppear {
            UIAccessibility.post(notification: .screenChanged,
                                 argument: "\(title). \(rationale)")
        }
    }

    private func checkAndAllow() {
        // If already determined, go straight to Settings recovery
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let micStatus = AVAudioSession.sharedInstance().recordPermission

        let alreadyDenied: Bool
        if systemImage == "camera.fill" {
            alreadyDenied = camStatus == .denied || camStatus == .restricted
        } else {
            alreadyDenied = micStatus == .denied
        }

        if alreadyDenied {
            // Show open-settings recovery
            deniedAndShowingRecovery = true
        } else {
            onAllow()
        }
    }
}

// MARK: - Onboarding slides

private struct Slide {
    let headline: String
    let body: String
    let glyph: GlyphKind
    enum GlyphKind { case teach, find, lock }
}

struct OnboardingView: View {
    var onDone: () -> Void

    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let slides: [Slide] = [
        Slide(
            headline: "Teach me your things.",
            body: "Record 4 short videos of an object \u{2014} your keys, mug, anything. I\u{2019}ll learn what it looks like.",
            glyph: .teach
        ),
        Slide(
            headline: "I\u{2019}ll help you find them.",
            body: "Point your phone around. I\u{2019}ll guide you with sounds and vibrations until the object is in reach.",
            glyph: .find
        ),
        Slide(
            headline: "Everything stays on your iPhone.",
            body: "Your videos and the AI model never leave your device.",
            glyph: .lock
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: progress dots + Skip
            topBar

            Spacer()

            // Glyph + headline + body
            slideContent
                .id(step)   // forces re-render for transition
                .transition(reduceMotion
                    ? .opacity
                    : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                  removal:   .move(edge: .leading).combined(with: .opacity)))
                .animation(.easeInOut(duration: 0.3), value: step)

            Spacer()

            // Continue / Start + Back
            bottomControls
        }
        .background(FMTTheme.background)
        .onAppear {
            UIAccessibility.post(notification: .screenChanged,
                                 argument: slides[step].headline)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            // Progress dots (active = 28pt wide, inactive = 8pt)
            HStack(spacing: 6) {
                ForEach(0..<slides.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(i == step ? FMTTheme.accent : FMTTheme.separator)
                        .frame(width: i == step ? 28 : 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: step)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Slide \(step + 1) of \(slides.count)")

            Spacer()

            Button(action: onDone) {
                Text("Skip")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FMTTheme.accent)
                    .frame(minWidth: 60, minHeight: 44)
            }
            .accessibilityLabel("Skip onboarding")
            .accessibilityHint("Skips the introduction and goes to Home")
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    // MARK: - Slide content

    private var slideContent: some View {
        VStack(spacing: 24) {
            OnboardingGlyph(kind: slides[step].glyph)
                .frame(width: 160, height: 160)
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                Text(slides[step].headline)
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(FMTTheme.text)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .accessibilityAddTraits(.isHeader)

                Text(slides[step].body)
                    .font(.system(size: 19))
                    .foregroundStyle(FMTTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 0) {
            let isLast = step == slides.count - 1

            Button {
                withAnimation {
                    if isLast { onDone() } else { step += 1 }
                }
            } label: {
                Text(isLast ? "Start" : "Continue")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(FMTTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(FMTTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: FMTTheme.Radius.row))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .accessibilityLabel(isLast ? "Start" : "Continue")
            .accessibilityHint(isLast
                ? "Finishes onboarding and opens Home"
                : "Goes to the next slide")

            if step > 0 {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    Text("Back")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(FMTTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityHint("Goes to the previous slide")
            } else {
                Color.clear.frame(height: 44)
            }
        }
        .padding(.bottom, 34)
    }
}

// MARK: - SVG-faithful glyphs (SwiftUI Canvas)

private struct OnboardingGlyph: View {
    let kind: Slide.GlyphKind

    var body: some View {
        Canvas { ctx, size in
            let c = UIColor(FMTTheme.accent)
            let sw: CGFloat = 4
            let cx = size.width / 2
            let cy = size.height / 2

            switch kind {
            case .teach:  drawTeach(ctx: ctx, cx: cx, cy: cy, c: c, sw: sw)
            case .find:   drawFind(ctx: ctx, cx: cx, cy: cy, c: c, sw: sw)
            case .lock:   drawLock(ctx: ctx, cx: cx, cy: cy, c: c, sw: sw)
            }
        }
    }

    // Camera/teach glyph: outer ring + viewfinder rect + lens circles
    private func drawTeach(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                           c: UIColor, sw: CGFloat) {
        let accent = Color(uiColor: c)

        // Outer ring
        var ring = Path()
        ring.addEllipse(in: CGRect(x: cx - 76, y: cy - 76, width: 152, height: 152))
        ctx.stroke(ring, with: .color(accent.opacity(0.25)), lineWidth: 3)

        // Camera body
        var body = Path()
        body.addRoundedRect(in: CGRect(x: cx - 38, y: cy - 24, width: 76, height: 58),
                            cornerSize: CGSize(width: 10, height: 10))
        ctx.stroke(body, with: .color(accent), lineWidth: sw)

        // Lens outer circle
        var lensOuter = Path()
        lensOuter.addEllipse(in: CGRect(x: cx - 14, y: cy - 9, width: 28, height: 28))
        ctx.stroke(lensOuter, with: .color(accent), lineWidth: sw)

        // Lens inner dot
        var lensDot = Path()
        lensDot.addEllipse(in: CGRect(x: cx - 6, y: cy - 1, width: 12, height: 12))
        ctx.fill(lensDot, with: .color(accent))

        // Viewfinder notch (top)
        var notch = Path()
        notch.addRoundedRect(in: CGRect(x: cx - 16, y: cy - 36, width: 32, height: 14),
                             cornerSize: CGSize(width: 4, height: 4))
        ctx.stroke(notch, with: .color(accent), lineWidth: sw)
    }

    // Find glyph: concentric rings + centre dot
    private func drawFind(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                          c: UIColor, sw: CGFloat) {
        let accent = Color(uiColor: c)
        let radii: [(CGFloat, Double)] = [(20, 1.0), (40, 0.55), (60, 0.3), (76, 0.15)]
        for (r, opacity) in radii {
            var ring = Path()
            ring.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            let lw: CGFloat = r == 20 ? sw : 3
            ctx.stroke(ring, with: .color(accent.opacity(opacity)), lineWidth: lw)
        }
        var dot = Path()
        dot.addEllipse(in: CGRect(x: cx - 6, y: cy - 6, width: 12, height: 12))
        ctx.fill(dot, with: .color(accent))
    }

    // Lock glyph: padlock body + shackle + keyhole
    private func drawLock(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                          c: UIColor, sw: CGFloat) {
        let accent = Color(uiColor: c)

        // Lock body
        var body = Path()
        body.addRoundedRect(in: CGRect(x: cx - 40, y: cy - 2, width: 80, height: 62),
                            cornerSize: CGSize(width: 14, height: 14))
        ctx.stroke(body, with: .color(accent), lineWidth: sw)

        // Shackle (top arc)
        var shackle = Path()
        shackle.move(to: CGPoint(x: cx - 22, y: cy - 2))
        shackle.addLine(to: CGPoint(x: cx - 22, y: cy - 18))
        shackle.addArc(center: CGPoint(x: cx, y: cy - 18),
                       radius: 22,
                       startAngle: .degrees(180), endAngle: .degrees(0),
                       clockwise: false)
        shackle.addLine(to: CGPoint(x: cx + 22, y: cy - 2))
        ctx.stroke(shackle, with: .color(accent), lineWidth: sw)

        // Keyhole dot
        var dot = Path()
        dot.addEllipse(in: CGRect(x: cx - 6, y: cy + 18, width: 12, height: 12))
        ctx.fill(dot, with: .color(accent))

        // Keyhole stem
        var stem = Path()
        stem.move(to: CGPoint(x: cx, y: cy + 30))
        stem.addLine(to: CGPoint(x: cx, y: cy + 38))
        ctx.stroke(stem, with: .color(accent),
                   style: StrokeStyle(lineWidth: sw, lineCap: .round))
    }
}

#Preview("Onboarding") { OnboardingView { } }
#Preview("Permissions") { PermissionsFlow { } }
