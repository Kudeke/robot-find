# Handoff: Find My Things — iOS App for Blind & Low-Vision Users

> **For the developer using Claude Code:** This bundle is a complete design specification for an accessibility-first iOS app. Read this README first, then look at the HTML prototype to see the designs in motion. Implement in **SwiftUI (iOS 17+)**.

---

## 1. Overview

**Find My Things** is an iOS app that lets blind and low-vision users teach an on-device AI to recognize their personal objects (keys, mug, white cane, medication bottle, etc.), then find those objects in their environment using real-time camera scanning with multimodal (audio + haptic + visual) guidance.

**Core flows:**
1. **Teach** — record 4 short videos of an object → on-device few-shot model trains in seconds
2. **Find** — scan the environment with the camera; the app guides the user via sonar-style audio pings, stereo panning, haptic pulses, and spoken nudges until the object is in arm's reach

**Reference apps:** Microsoft Seeing AI, Be My Eyes, Envision, Apple's Magnifier.

---

## 2. About the Design Files

The files in `prototype/` are **design references created in HTML/React**. They show intended look, layout, copy, interactions, accessibility annotations, and audio/haptic feedback patterns. **They are NOT production code to copy.**

Your task is to **recreate these designs in SwiftUI** using:
- Native SwiftUI components (`NavigationStack`, `List`, `Button`, etc.)
- `AVFoundation` for camera
- `Vision` + `Core ML` for object recognition (the user is implementing the few-shot model separately)
- `CoreHaptics` for vibration patterns
- `AVSpeechSynthesizer` for spoken guidance
- `AVAudioEngine` (or `AudioToolbox`) for sonar pings
- Full VoiceOver support via `.accessibilityLabel()` / `.accessibilityHint()` / `.accessibilityAddTraits()`

The `swift_starter/` folder contains a **partial implementation** (Home screen + design tokens + 2 reusable components) that establishes the patterns to follow. Continue from there.

---

## 3. Fidelity

**High-fidelity.** The HTML prototype has final colors (exact hex), typography (SF Pro at specific sizes/weights), spacing (8pt grid), corner radii, shadows, and accessibility annotations. Recreate pixel-accurately, but use SwiftUI-native patterns where they're a better fit (e.g., use SF Symbols instead of inline SVG icons).

---

## 4. Target Device

**iPhone 12 Pro Max** (428 × 926 pt) is the design target. Layout must work down to iPhone SE (375 × 667) and adapt up to iPhone 15 Pro Max.

---

## 5. Design System / Tokens

### Colors

**Light mode** (default — implement first):
| Token | Hex | Use |
|---|---|---|
| `background` | `#FFFFFF` | Screen background |
| `backgroundGrouped` | `#F2F2F7` | Grouped list background |
| `surface` | `#FFFFFF` | Cards, rows |
| `text` | `#000000` | Primary text |
| `textSecondary` | `rgba(60,60,67,0.78)` | Subtitles, captions |
| `textTertiary` | `rgba(60,60,67,0.45)` | Chevrons, dimmed |
| `separator` | `rgba(60,60,67,0.18)` | Hairlines |
| `accent` | `#0040DD` | CTAs (WCAG AAA on white) |
| `onAccent` | `#FFFFFF` | Text on accent |
| `success` | `#005A2B` | "Ready" status, found state |
| `successBg` | `#D9F2E2` | Success badge background |
| `warning` | `#A04500` | "Needs training" |
| `warningBg` | `#FFF1E0` | Warning badge background |
| `error` | `#B00020` | Destructive, low confidence |
| `chipBg` | `#EEF1FB` | Suggestion chips, secondary buttons |
| `fieldBg` | `#F2F2F7` | Text field background |

**Dark mode:**
| Token | Hex |
|---|---|
| `background` | `#000000` (true black, OLED) |
| `surface` | `#1C1C1E` |
| `text` | `#FFFFFF` |
| `textSecondary` | `rgba(235,235,245,0.7)` |
| `accent` | `#4D8BFF` |
| `success` | `#4ADE80` |

**High Contrast** (when iOS Increase Contrast is on): bump all text/element pairs to ≥ 7:1. Accent becomes `#FFD60A` (yellow on black) with `#000` text on it for max contrast.

Full token definitions in `prototype/theme.jsx` (`FMT_THEMES` object).

### Typography

**Font:** SF Pro (system default).

**Type scale** (default Dynamic Type):
| Role | Size | Weight | Letter spacing |
|---|---|---|---|
| Large title | 34pt | Bold (700) | -0.6 |
| Screen title | 28-30pt | Bold (700) | -0.5 |
| Section header | 22pt | Bold (700) | -0.4 |
| Item name (in row) | 22pt | Bold (700) | -0.3 |
| Button label | 22pt | Semibold (600) | -0.3 |
| Body | 17-19pt | Regular/Medium | -0.43 |
| Caption | 14-15pt | Medium (500) | normal |
| Eyebrow / uppercase | 13pt | Semibold (600) | +0.5 (uppercase) |

**Use SwiftUI's Dynamic Type** (`.font(.system(.title))`, `.font(.system(.body))`) so text scales with user's iOS setting. Layout MUST reflow at AX5 (310%) — stack instead of inline at large sizes, no truncation.

### Spacing — 8pt grid

| Token | Value |
|---|---|
| `xs` | 4 |
| `s` | 8 |
| `m` | 12 |
| `l` | 16 |
| `xl` | 20 (screen edge insets) |
| `xxl` | 32 |

### Radii

| Use | Radius |
|---|---|
| Rows, buttons | 18pt |
| Cards | 22pt |
| Fields | 14pt |
| Chips, badges | 999 (capsule) |
| Sheets | 27pt |

### Touch targets

- **Minimum 60×60pt** (above HIG's 44pt — non-visual tapping needs more room)
- **Minimum 16pt** between adjacent tappable items

### Iconography

- **SF Symbols only**, weight: regular or bold
- Always pair with a text label (only Settings gear and Close X are icon-only)
- Min icon size 28pt; scales with Dynamic Type
- Specific symbols used: `magnifyingglass`, `plus`, `chevron.left/right`, `gearshape`, `questionmark.circle`, `xmark`, `checkmark`, `mic.fill`, `trash`, `bolt.fill`, `speaker.wave.2.fill`, `flashlight.on.fill`

---

## 6. Information Architecture

```
Splash + Permissions (one-at-a-time: camera, mic, haptic)
  ↓
Onboarding (3 slides, skippable, replayable)
  ↓
HOME ──────────────────────────────────────────────────┐
  ├─ Find an item       → Item Picker → Scanning → Found
  ├─ Teach a new item   → Teach Wizard (5 steps)
  ├─ My Items list      → Item Detail → [Find | Re-train | Delete]
  ├─ Settings (gear)
  │   ├─ Voice & Speech (verbosity, rate, voice)
  │   ├─ Haptics (on/off, intensity, test)
  │   ├─ Audio cues (sonar style, panning, found chime, volume)
  │   ├─ Camera & Detection (sensitivity, LiDAR, low-light, max scan time)
  │   ├─ Privacy (on-device explainer)
  │   └─ Help (replay onboarding, tutorials, feedback)
  └─ Quick Help (floating, always reachable)
```

**Tab bar:** none in current design — Home acts as the hub. (If you add a tab bar later, use 3 large tabs: Find · Teach · Library. Hide it in Scanning and Teach-recording for full-screen immersion.)

---

## 7. Screens — Detailed Specifications

For **every** screen below, the prototype HTML is the source of truth for visual layout. This README captures behavior, copy, accessibility annotations, and edge cases.

### 7.1 Splash + Permissions (NEW — not in prototype, build from spec)

- App name spoken aloud on launch: `"Find My Things. Loading."`
- Request **camera, microphone, haptic** permissions one at a time, each on its own screen
- Each: plain-language rationale, big "Allow" button (full-width, 72pt tall), "Why we need this" disclosure
- Don't proceed until permission resolved; if denied, show a recovery screen with "Open Settings" deep link

### 7.2 Onboarding — 3 slides

Prototype: see `ScreenOnboarding` in `screens-onboarding-home.jsx`.

| Slide | Headline (≤8 words) | Body |
|---|---|---|
| 1 | "Teach me your things." | "Record 4 short videos of an object — your keys, mug, anything. I'll learn what it looks like." |
| 2 | "I'll help you find them." | "Point your phone around. I'll guide you with sounds and vibrations until the object is in reach." |
| 3 | "Everything stays on your iPhone." | "Your videos and the AI model never leave your device." |

**Layout:** SVG glyph (160×160) centered, headline (32pt bold, balanced wrap), body (19pt secondary, pretty wrap), full-width "Continue"/"Start" button (72pt tall) at bottom. Pill progress dots at top (active dot 28pt wide, inactive 8pt). "Skip" button top-right (60×60 hit area, 17pt accent).

**Behavior:** Respects Reduce Motion — replace any slide animation with cross-fade. Each slide's headline is `.accessibilityAddTraits(.isHeader)`. Body is automatically read by VoiceOver when the slide gains focus. "Skip" finishes onboarding and navigates to Home.

### 7.3 Home

Prototype: `ScreenHome` in `screens-onboarding-home.jsx`. Swift starter: `swift_starter/HomeView.swift` (already implemented — use as reference).

**Layout (top → bottom):**
1. Large title "Find My Things" + greeting subtitle "Hello. You have *N* items saved." (VoiceOver reads on screen open). Settings gear top-right (44×44).
2. **Primary button "Find an item"** — full-width, 96pt tall, accent bg, magnifier icon + label + "Scan with the camera" sublabel
3. **Secondary button "Teach a new item"** — same dimensions, secondary bg (`chipBg`), plus icon + label + "Record 4 short videos" sublabel
4. **My items section** — header "My items" (22pt bold) + `N saved` count, then list of rows
5. **Item rows** (80pt min height, 18pt radius): 56pt thumbnail (gradient swatch), name (22pt bold, 1-line truncate), status badge ("Ready" green / "Needs training" amber) + last-used timestamp, trailing chevron
6. **Quick Help button** — full-width, 60pt, dashed border, "Quick help" label + question-mark icon

**VoiceOver reading order:** Greeting → Find → Teach → each item row in order → Quick Help → Settings (top-right).

**Accessibility per row:** `accessibilityLabel("\(name). \(status). Last used \(time).")`, `accessibilityHint("Opens item details")`, `accessibilityAddTraits(.isButton)`.

### 7.4 Library

Prototype: `ScreenLibrary` in `screens-onboarding-home.jsx`.

Same row style as Home. Adds:
- Search field (with mic for dictation) — 48pt tall, `fieldBg`, magnifier icon + "Search items" placeholder + mic icon
- Plus button top-right (starts Teach wizard)
- VoiceOver Custom Actions on each row: **Find**, **Re-train**, **Rename**, **Delete** (use `.accessibilityCustomContent` or swipe actions)

### 7.5 Item Detail

Prototype: `ScreenItemDetail` in `screens-onboarding-home.jsx`.

- Large title = item name, subtitle = "Trained Apr 22, 2026 • 4 videos"
- **Recognition card**: thumbnail (88pt) + "RECOGNITION" eyebrow + confidence label colored by level ("High confidence" green / "Medium" amber / "Low — re-train" red)
- **Training videos strip**: horizontally scrolling 110×150 thumbnails, each with play button overlay and angle label ("Front", "Side", "Top", "Other bg")
- **3 action buttons**: "Find this item" (primary), "Add more training videos" (secondary), "Delete item" (destructive — pink bg, error text)
- Delete confirms with spoken summary + 3-second Undo toast (per spec — not yet in prototype)

### 7.6 Teach Wizard — 5 steps

Prototype: `ScreenTeach` in `screens-teach.jsx`.

**Common chrome:** Top bar with Cancel/Back (60×60), centered "Step N of 5" pill, 5-segment progress bar (each segment fills as steps complete).

**Step 1 — Name your item**
- Title "Name your item", subtitle "What do you want to call this item? You can dictate by tapping the microphone."
- Text field (22pt bold input, accent border, 16pt radius) with mic button
- Suggestion chips below: "Keys", "Wallet", "White cane", "Headphones", "Mug", "Remote", "Phone charger", "Medication" — tap to autofill
- "Next" button at bottom (68pt). Disabled until name has content.

**Step 2 — Get ready**
- Title "Get ready", subtitle: `"Place [item name] on a flat surface in good lighting. Make sure nothing else cluttered is around it. Tell me when you're ready."`
- Tips card with 4 checkmark bullets: contrasting background, hold phone ~1 ft away, 4 videos from different angles, ~5 sec each
- "I'm ready" button (primary, 68pt) + "Get help framing" ghost button below

**Step 3 — Record 4 videos** ⭐ Critical
- **Black background** (full-screen camera mode)
- Top: "Video N of 4" eyebrow + angle label ("Front view" / "Side view" / "Top view" / "Different background")
- Camera viewfinder (rounded 24pt rect) with corner brackets (yellow #FFD60A, 3pt) at framing corners. Mock object centered, rotates slightly between clips
- "REC" pill (red bg, pulsing dot) appears top-center while recording
- Live coaching caption at bottom of viewfinder: `"Hold the phone about one foot away."` → during recording: `"✓ Good, keep going. Move slowly."`
- 4 progress bars below viewfinder (filled green as clips are saved)
- **Big record button** (96pt circle, white outer ring + red inner) — tap to record (~1.8 sec mock duration). When recording, inner red shrinks to a 32pt rounded square.
- "Tap to record" / "Recording…" / "Tap Next to train the model" status text
- After 4 clips: button disables, "Train now" primary button enables

**Audio/haptic during recording:**
- Continuous low hum so user knows it's recording
- Haptic ticks each second
- Spoken countdown at "2, 1, done"
- Real-time framing feedback spoken: "Move closer", "Object out of frame", "Good, keep going"

**Step 4 — Training**
- Centered 200×200 progress ring (10pt stroke, accent color, smooth `strokeDashoffset` animation)
- Big % readout in center → checkmark when done
- Title "Teaching me…" → "Done!" / Subtitle: "Teaching me about your *[name]*. This will take just a few seconds." → "I learned your *[name]*."
- Haptic pulse every 25%, audible ticks during progress, success chime on completion
- "Continue" button enables at 100%

**Step 5 — Try it now**
- Big green checkmark in 140pt success-bg circle
- Title "All set", body: "I can now find your *[name]*. Want to try it?"
- Two buttons: **"Try finding it now"** (primary, jumps to Scanning with this item preselected) + **"Save and finish"** (secondary, returns Home)

### 7.7 Find Flow

#### 7.7a Item Picker

Prototype: `ScreenItemPicker` in `screens-find.jsx`.

Modal sheet. Top: Cancel (60pt), centered title "Find an item". Search field (same as Library). Two grouped sections: **Recently used** (top 3) and **All items** (rest). Each row 80pt: thumbnail (48pt) + name (20pt bold) + last-used. Tap → start scanning.

#### 7.7b Scanning Screen ⭐⭐ Most critical

Prototype has **3 visual variants** (`bar`, `radar`, `heatmap`) selectable via Tweaks. **Pick the variant the team commits to** before implementing — they share the same data model but different visuals.

**Recommended starting variant: `bar` (Sonar bar)** — minimal, audio-first, clearest mapping to the proximity/direction model. Other two are alternative directions to explore later.

**Common to all variants:**
- Full-screen camera preview
- Top header (z=5) with gradient fade: "LOOKING FOR" eyebrow + item name (22pt bold) + Stop button (60×60, dark bg, white close X)
- Visible target reticle/crosshair in center
- Bottom HUD with caption strip + proximity indicator + (when found) Confirm button

**Behavior — proximity model:**
- `proximity` ∈ [0, 1] derived from model confidence × inverse distance (LiDAR if available, else size estimate)
- `direction` ∈ [-1, 1] left/right offset of detected bounding box from frame center
- Phases: `searching` (proximity < 0.6) / `warm` (0.6–0.92) / `found` (> 0.92, sustained 1+ second) / `lost` (was found, now out-of-frame > 2 sec)

**Audio (the actual UI for blind users):**
- **Sonar pings** — sine wave, frequency `440 + proximity × 800` Hz, repeat rate `0.5 + proximity × 7.5` Hz (0.5Hz cold → 8Hz very warm). 12ms attack, 120ms exponential decay, ~0.18 gain. See `useSonar` in `screens-find.jsx` for reference.
- **Stereo panning** — pan ping based on `direction` (left/right) so user knows which way to turn
- **Pitch rises** as confidence increases
- **Spoken nudges** every 3 sec (configurable by Verbosity setting): "Move slightly right." · "Tilt up." · "Getting warmer." · "It's about 2 feet ahead."
- **Found chord** — C major arpeggio, 600ms + spoken: "Found your *[name]*. About *[X]* foot in front of you, slightly to your right."
- **Lost cue** — gentle descending tone after 2 sec out-of-frame + spoken: "I lost it. Pan slowly."
- **NEVER speak over VoiceOver** — pause `AVSpeechSynthesizer` when `UIAccessibility.isVoiceOverRunning`; route nudges through VO `accessibilityAnnouncementNotification` instead.

**Haptics (CoreHaptics continuous + transient pattern):**
- Continuous proximity pulse — pulse rate matches audio ping rate
- Found: `UINotificationFeedbackGenerator.success` + 2 sharp taps
- Out-of-frame: soft warning rumble
- LiDAR mode (Pro/Pro Max): stronger pulse when within ~50cm

**Gestures:**
- **Single tap anywhere** → repeat last spoken instruction
- **Two-finger double-tap** (Magic Tap) → pause/resume scanning
- **Three-finger swipe down** → exit scanning
- **Long-press anywhere** → describe full scene (calls fallback general scene description model)

**VoiceOver mode:** When VO is on, the entire camera preview becomes one accessible element with custom rotor actions: "Repeat", "Describe scene", "Pause", "Stop".

**Variant A — Sonar bar** (`ScanningVariantBar`)
- Bottom HUD: caption strip (16pt radius, blurred bg) showing direction + distance
- Horizontal proximity bar (14pt height, 7pt radius) — gradient blue→yellow→red, fills based on proximity
- "Cold / Getting warmer / Hot" labels above bar
- Triangular direction indicator that slides left/right based on `direction`

**Variant B — Radar** (`ScanningVariantRadar`)
- Centered 320pt radar with concentric rings, expanding pulse circles, sweep arm rotated by direction
- Target blip (yellow/red dot) positioned by direction angle and proximity-derived radius
- 3 HUD tiles below: Distance / Confidence / Direction
- Big readout "Getting warmer…" / "Found! Tap to confirm"

**Variant C — Heatmap** (`ScanningVariantHeatmap`)
- Color-coded radial gradient overlay on camera (cold blue → warm orange → hot yellow)
- Persistent bounding box around the detected object, tagged "RED COFFEE MUG • 87%" label above box
- Edge chevron arrows (yellow) animate when direction is far off-center
- 5-segment proximity bar at bottom (cold→hot color stops)
- Big distance readout: "5.2 ft ahead"

#### 7.7c Found

Prototype: `ScreenFound` in `screens-find.jsx`.

- 156pt success circle (success bg, big checkmark)
- Title "Found!" (36pt bold success color)
- Item name (22pt) + spatial description "About 1 foot ahead, slightly to your right." (17pt secondary)
- Three full-width buttons: **"Find again"** (primary), **"Find another item"** (secondary), **"Done"** (ghost)
- Auto-speaks result. **Does NOT auto-dismiss** (per spec — blind users navigate slower).

### 7.8 Settings

Prototype: `ScreenSettings` in `screens-teach.jsx`.

Grouped iOS-style list (`backgroundGrouped`, 18pt radius cards in `surface`). Sections:
- **Voice & Speech**: Verbosity (Concise/Standard/Detailed), Speech rate (slider), Voice (picker)
- **Haptics**: Master toggle (with `accessibilityValue`), Intensity, "Test haptic"
- **Audio cues**: Sonar style (Ping/Beep/Sine wave/Voice only), Stereo panning toggle, Found chime, Volume slider, "Test sound"
- **Camera & Detection**: Sensitivity (Conservative/Balanced/Aggressive), LiDAR (Auto/On/Off), Low-light boost, Max scan time
- **Privacy & Help**: "All data is on this device" disclosure, Replay onboarding, Tutorial videos, Send feedback

Each row: 56pt min height, label (17pt) + trailing value (16pt secondary) + chevron OR iOS-style toggle. Every toggle MUST have an `accessibilityValue` ("Haptics: On").

### 7.9 Quick Help (modal sheet)

Prototype: `ScreenHelp` in `screens-teach.jsx`.

Bottom sheet with grabber, large "Quick help" title + "Always one tap away." subtitle, 4 list rows:
- "How to teach an item" — 5 steps, about 2 minutes
- "How to find an item" — Sounds and vibrations guide you
- "Contact a sighted helper" — Opens Be My Eyes if installed (URL scheme `bemyeyes://`), else dial saved emergency contact
- "Replay onboarding" — Replays the 3-slide intro

Each row 76pt: 44pt icon tile (chip-bg) + title (19pt bold) + subtitle (15pt secondary) + chevron.

---

## 8. Error & Edge States (every screen must handle these)

| State | Behavior |
|---|---|
| **No items yet** (empty Library/Home) | Show: "You haven't taught me any items yet. Tap *Teach a new item* to start." |
| **Camera permission denied** | Plain explanation + "Open Settings" deep link button |
| **Mic permission denied** (dictation) | Hide mic icons, fall back to keyboard input only |
| **Scanning timeout** (60s no detection) | Speak: "I couldn't find your *[item]* nearby. Want to try a different room or re-train?" + retry/cancel buttons |
| **Object likely covered** (low confidence sustained) | "I think it might be hidden. Try opening drawers or moving closer." |
| **Low light** (after 5s of low confidence + low light) | Auto-suggest: "It's dark here. Tap to turn on the flashlight." |
| **Battery low while scanning** | Warn at 15%, pause and ask at 5% |
| **Storage full** (cannot save more videos) | Block teach, show: "Your iPhone is out of space. Delete an item to free space." + path to Library |
| **Multiple matches in frame** | Speak: "I see two possible matches. Pick the closer one? Tap once for closer, twice for farther." |
| **Model failed to train** | Friendly error + "Re-record videos" CTA. Never show stack traces. |

---

## 9. Audio + Haptic Feedback Spec Sheet

### Sonar (continuous, scanning screen)
| Param | Mapping |
|---|---|
| Repeat rate | `0.5 + proximity × 7.5` Hz |
| Frequency | `440 + proximity × 800` Hz (sine) |
| Pan | `direction` × 1.0 (full L/R) |
| Envelope | 12ms linear attack, 120ms exponential decay |
| Gain | 0.18 peak |

### Spoken nudges
- Throttled to **max 1 per 3 seconds**
- Phrases: "Move slightly right.", "Tilt up.", "Getting warmer.", "It's about *X* feet ahead."
- Pause when VO is active; route through VO announcement

### Found cue
- C major arpeggio (C4-E4-G4-C5), 600ms total
- + Haptic: `.success` notification + 2 sharp transients (CoreHaptics)
- + Spoken: "Found your *[item]*. About *[X]* foot in front of you, *[direction]*."

### Lost cue
- Descending tone (G4 → C4), 400ms
- + Soft haptic rumble (continuous, 0.3 intensity, 600ms)
- + Spoken (after 2s): "I lost it. Pan slowly."

### Recording (Teach step 3)
- Continuous low hum (220 Hz sine, 0.05 gain) — confirms recording is active
- Haptic tick each second (`UIImpactFeedbackGenerator.light`)
- Spoken countdown at "2, 1, done"

### Training progress
- Audible tick every 25%
- Haptic pulse every 25%
- Success chime at completion (same C major arpeggio)

---

## 10. Accessibility Requirements (mandatory)

For **every** interactive element, set:
1. `.accessibilityLabel("…")` — what the element is, plain language
2. `.accessibilityHint("…")` — what happens when activated, starts with a verb ("Opens…", "Starts…")
3. `.accessibilityValue("…")` — for sliders, toggles, progress
4. `.accessibilityAddTraits(…)` — `.isButton`, `.isHeader`, `.updatesFrequently`, `.isImage`, etc.

**The HTML prototype encodes these as `data-fmt-label`, `data-fmt-hint`, `data-fmt-trait` attributes on every element.** Grep for these attributes in `prototype/*.jsx` to extract the exact strings.

**Checklist (verify before shipping):**
- [ ] A totally blind user can complete Teach + Find end-to-end with VoiceOver, no sighted assistance
- [ ] Every screen has a clear, predictable VoiceOver reading order
- [ ] Every interactive element has label + hint + traits
- [ ] Every visual cue has audio AND haptic equivalent
- [ ] All touch targets ≥ 60×60pt
- [ ] All text passes WCAG AA (4.5:1) at minimum, AAA (7:1) where feasible
- [ ] Layout reflows correctly at AX5 Dynamic Type with no truncation
- [ ] No flow has a hard timeout shorter than 30 seconds
- [ ] Every error state is recoverable
- [ ] Light, Dark, and High Contrast variants all implemented
- [ ] Reduce Motion respected (replace slides/parallax with cross-fades)
- [ ] No flashing > 3 Hz (seizure safety)

---

## 11. Don'ts (from the original brief)

- ❌ Don't rely on color, position, or animation alone for any meaningful information
- ❌ Don't auto-dismiss anything important
- ❌ Don't use modals stacked more than one deep
- ❌ Don't put critical actions in swipe-only gestures without an equivalent button
- ❌ Don't use placeholder text as the only label for an input
- ❌ Don't design tiny inline icon-only buttons
- ❌ Don't assume the user can frame the camera — guide them
- ❌ Don't speak over VoiceOver — always pause synthesizer when VO is active
- ❌ Don't require an internet connection for any core flow
- ❌ Don't show a tutorial that can't be replayed

---

## 12. Files in this bundle

```
design_handoff_find_my_things/
├── README.md                          ← you are here
├── original_brief.md                  ← the full original product/design brief
├── prototype/
│   ├── Find My Things.html            ← the interactive prototype, open in any browser
│   ├── theme.jsx                      ← all design tokens (FMT_THEMES, type scale, icons)
│   ├── ios-frame.jsx                  ← iPhone bezel + status bar (reference only)
│   ├── tweaks-panel.jsx               ← in-prototype controls (reference only)
│   ├── screens-onboarding-home.jsx    ← Onboarding, Home, Library, Item Detail
│   ├── screens-teach.jsx              ← Teach wizard (5 steps), Settings, Help
│   └── screens-find.jsx               ← Item Picker, Scanning (3 variants), Found
└── swift_starter/
    ├── FMTTheme.swift                 ← design tokens as Swift constants
    ├── FMTComponents.swift            ← FMTBigButton + FMTItemRow + FMTItemThumbnail
    └── HomeView.swift                 ← complete Home screen + FMTItem model + seed data
```

**To view the prototype:** Open `prototype/Find My Things.html` in Chrome/Safari. Use the floating Tweaks panel to switch theme, Dynamic Type size, scanning variant, toggle VoiceOver overlay, etc. Use the dark pill at top to jump between screens.

**To extract any visual detail:** Read the corresponding `.jsx` file. Inline styles are explicit (no Tailwind, no abstraction layers).

---

## 13. Recommended implementation order

1. Wire up `FMTTheme.swift` + `FMTComponents.swift` (already provided) and confirm Home matches prototype
2. **Item Detail** view (similar pattern to Home rows)
3. **Settings** view (`Form` / `List` with sections)
4. **Library** view (Home rows + search field)
5. **Teach Wizard** — start with Step 1 (text input + chip suggestions), then Step 2/4/5 (mostly static), then Step 3 last (camera-heavy)
6. **Item Picker** sheet
7. **Scanning screen** — implement the proximity/direction state machine first, then the chosen visual variant, then audio (`AVAudioEngine`), then haptics (`CoreHaptics`)
8. **Found** screen
9. **Onboarding + Permissions**
10. **Edge/error states** for each screen
11. **VoiceOver pass** — complete walkthrough with screen reader on, fix every gap
12. **Dynamic Type pass** — test at AX5, fix overflow
13. **Dark mode + High Contrast** — verify in Settings

---

## 14. Questions while implementing?

Refer to `original_brief.md` for the original product specification (deliverables, target users, success criteria). The prototype is the source of truth for visuals; the brief is the source of truth for behavior and intent.

When in doubt: **the user is blind. Every state must be conveyed without looking at the screen.**
