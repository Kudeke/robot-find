# Prompt: Find My Things — Accessible iOS App for Blind & Low-Vision Users

> 把以下内容**整段复制**贴到 Claude Design / Claude Designer 即可。Prompt 已包含产品定义、用户画像、信息架构、屏幕清单、交互细节、视觉与无障碍规范、技术约束与验收标准。

---

## ROLE

You are a senior product designer specializing in **accessibility-first mobile design** for blind and low-vision users on iOS. You design with VoiceOver as the *primary* interaction layer, not as an afterthought. Your reference apps are **Microsoft Seeing AI**, **Be My Eyes**, **Envision**, **Supersense**, and Apple's **Magnifier** app.

## TASK

Design a complete, production-ready iOS app called **"Find My Things"** that lets blind and low-vision users **teach an on-device AI to recognize their personal objects**, then **find those objects in their environment** using real-time camera scanning with multimodal (audio + haptic + visual) guidance.

Deliver: full information architecture, every screen, every state, every interaction, every accessibility annotation, and a design system tuned for non-visual use.

---

## PRODUCT CONTEXT

### Problem
Blind and low-vision people frequently misplace personal items (keys, white cane, headphones, wallet, TV remote, mug, medication bottle). Generic object recognizers only know "keys" in the abstract — they can't find *your specific keys* on *your* cluttered desk.

### Solution
A **teachable AI** built on few-shot learning. Users record 4 short videos of an object from different angles → the model personalizes on-device in seconds → later, the user scans their environment and the app guides them to within arm's reach via audio pings, spoken directions, and haptic pulses.

### Core technology assumed
- **On-device few-shot model** (think MobileCLIP / ORBIT-style prototypes) — no cloud round-trip
- **iOS 17+**, iPhone 12+ (Neural Engine, ideally LiDAR for distance estimation)
- **Core ML + Vision framework** for inference
- **AVFoundation** for camera, **CoreHaptics** for vibration, **AVSpeechSynthesizer** for spoken guidance

---

## TARGET USERS

**Primary:** Totally blind adults who use VoiceOver daily, are comfortable with iPhone gestures, and rely on audio + haptic feedback exclusively.

**Secondary:** Low-vision users who use both residual vision and VoiceOver, often with **high contrast, larger Dynamic Type, and reduced motion** enabled.

**Tertiary:** Sighted helpers (family, orientation & mobility specialists) assisting during initial setup.

### Design principles derived from this audience
1. **Audio-first, not audio-also.** Every state, transition, and result must be conveyed without looking at the screen.
2. **Single-finger reachability.** Critical actions must work with one thumb while the other hand holds the cane or the object.
3. **No timeouts on critical flows.** Blind users navigate slower with VoiceOver — never auto-dismiss anything important.
4. **Haptic + audio redundancy.** Every audio cue has a haptic counterpart (deaf-blind users; noisy environments).
5. **Forgiving framing.** Users can't see the camera viewfinder — the app guides framing with spoken/haptic feedback.
6. **Predictable structure.** Same gesture = same outcome on every screen. No clever, novel patterns.
7. **Big touch targets.** Minimum **60×60 pt** (Apple HIG minimum is 44×44; we go larger for non-visual tapping).

---

## INFORMATION ARCHITECTURE

```
Onboarding (first launch only)
   │
   ▼
HOME ─────────────────────────────────────────────┐
 ├─ Find an Item              → Item Picker → Scanning → Found
 ├─ Teach New Item             → Teach Wizard (5 steps)
 ├─ My Items (library)         → Item Detail → [Edit | Re-train | Delete]
 ├─ Settings
 │   ├─ Voice & Speech
 │   ├─ Haptics
 │   ├─ Audio cues (sonar style)
 │   ├─ Camera & Detection
 │   ├─ Help & Tutorials
 │   └─ About
 └─ Quick Help (always reachable)
```

**Tab bar:** 3 large tabs across the bottom — `Find` · `Teach` · `Library`. Settings is in a top-right gear button. Tab bar persists everywhere except inside the camera scanning and teach-recording screens (which go full-screen for immersive audio).

---

## SCREENS — DETAILED SPECIFICATIONS

### 0. Splash + Permission

- App name spoken aloud on launch (`"Find My Things. Loading."`).
- Request **camera + microphone (for voice commands) + haptic** permissions with plain-language rationale, one at a time, each on its own screen with a single big "Allow" button and a "Why we need this" disclosure.

### 1. Onboarding (first run only, skippable)

Three slides, each: a **single short sentence** as the headline (≤8 words), a **detailed description** below (which VoiceOver reads automatically when the slide gains focus), and one big bottom button.

| Slide | Headline | Body |
|---|---|---|
| 1 | "Teach me your things." | "Record 4 short videos of an object — your keys, mug, anything. I'll learn what it looks like." |
| 2 | "I'll help you find them." | "Point your phone around. I'll guide you with sounds and vibrations until the object is in reach." |
| 3 | "Everything stays on your iPhone." | "Your videos and the AI model never leave your device." |

Bottom: **"Start"** button (full-width, 72 pt tall). Top-left: **"Skip"** (still 60×60 pt hit area).

### 2. Home

Layout (top → bottom):
1. **Greeting strip** (subtle): "Hello. You have *N* items saved." VoiceOver reads on screen open.
2. **Big primary button: "Find an item"** — full-width, 96 pt tall, accent background, large icon (magnifier) + label.
3. **Big secondary button: "Teach a new item"** — same size, secondary background, plus icon + label.
4. **My Items list** — scrollable, each row 80 pt tall. Each row: item name (large, 22 pt bold), small status badge ("Ready" or "Needs more training"), trailing chevron. Tap → Item Detail.
5. **Floating "Quick Help" button** bottom-right (60 pt circle) — opens contextual tips.

VoiceOver order: Greeting → Find → Teach → list (each item) → Help → Settings (top-right gear).

### 3. Find Flow

#### 3a. Item Picker

Modal sheet with a vertical list of all taught items.
- Each row 80 pt, item name + last-used timestamp.
- **Search field at top** (works with dictation).
- **Recently used items** pinned to top.
- Tap an item → start scanning.

#### 3b. Scanning Screen ⭐ (the most critical screen)

Full-screen camera view. Visual layer is *minimal* because most users won't see it; what matters is the audio/haptic feedback.

**Visual layer (for low-vision and sighted helpers):**
- Large camera preview filling the screen
- Centered crosshair / target reticle
- Big text overlay at top: current target item name ("Looking for: red coffee mug")
- Bottom: a **distance/proximity bar** that fills as you get warmer
- Bounding box drawn over the detected object when found, with a high-contrast outline (4 pt yellow on dark, 4 pt black on light)
- Top-right: **Stop** button (60×60 pt, high contrast)

**Audio layer (the actual UI for blind users):**
- **Sonar pings**: a soft pulse that **speeds up as you get closer** — like a metal detector or parking sensor. Rate ranges from ~0.5 Hz (cold) to ~8 Hz (very warm).
- **Stereo panning**: ping pans **left/right** to indicate which way to turn the phone.
- **Pitch shift**: pitch rises as confidence increases.
- **Spoken nudges** (every ~3 seconds, configurable): "Move slightly right." · "Tilt up." · "Getting warmer." · "It's about 2 feet ahead."
- **Found cue**: a distinct, satisfying chord + spoken: "Found your red coffee mug. About 1 foot in front of you, slightly to your right."
- **Lost cue**: gentle descending tone if the object goes out of frame for >2 seconds, with: "I lost it. Pan slowly."

**Haptic layer:**
- **Continuous proximity haptic**: pulse rate matches the audio ping rate (CoreHaptics continuous pattern).
- **Found haptic**: distinctive double-tap (`UINotificationFeedbackGenerator.success`).
- **Out-of-frame haptic**: soft warning rumble.

**Gestures on the scanning screen:**
- **Single tap anywhere** → repeat last spoken instruction
- **Two-finger double-tap** → pause/resume scanning (VoiceOver Magic Tap convention)
- **Three-finger swipe down** → exit scanning
- **Long-press anywhere** → describe full scene (calls a fallback general scene description)

**LiDAR mode (iPhone Pro):** Adds spoken distance in feet/meters and a stronger haptic pulse when within arm's reach (~50 cm).

#### 3c. Found Screen

After confirmed find:
- Large success message: "Found! Red coffee mug, about 1 foot ahead, slightly right."
- Three big buttons: **"Find Again"** · **"Find Another Item"** · **"Done"**
- Auto-speaks result; does NOT auto-dismiss.

### 4. Teach Flow ⭐ (the second-most critical flow)

A 5-step wizard. Each step: clear progress indicator ("Step 2 of 5"), one focused action, one big "Next" button (and "Back").

#### Step 1 — Name your item
- Large text field (auto-focus invokes keyboard + dictation icon).
- Suggestions chips below: "Keys", "Wallet", "White cane", "Headphones", "Mug", "Remote", "Phone charger", "Medication bottle".
- Spoken hint: "What do you want to call this item? You can dictate by tapping the microphone."

#### Step 2 — Set up
- Spoken instructions: "Place the item on a flat surface in good lighting. Make sure nothing else cluttered is around it. Tell me when you're ready."
- Big button: **"I'm Ready"**.
- Optional: **"Get help framing"** → uses the camera to verify the object is centered and gives audio guidance ("move the phone closer", "more light needed").

#### Step 3 — Record 4 videos (the heart of the teach flow)
The model needs **4 short clips (~5 sec each), from different angles and backgrounds**, mirroring Microsoft's Find My Things approach. (Source: Microsoft Research's published description of the feature — videos shot from various angles and against different backgrounds.)

UX:
- Screen shows: **"Video 1 of 4 — Front view"** (then "Side view", "Top view", "Different background").
- Big record button (96 pt circle), centered.
- Spoken pre-record guidance: "Hold the phone about one foot away. Slowly move it around the item. Tap the big button when ready."
- During recording: a continuous low hum so user knows it's recording, plus haptic ticks each second; spoken countdown at "2, 1, done".
- **Real-time framing feedback** during recording: "Move closer" / "Object out of frame" / "Good, keep going."
- After each clip: "Video 1 saved. Tap to record video 2, or tap and hold to redo this one."
- All 4 clips required; user can preview and re-record any.

#### Step 4 — Training
- Spoken: "Teaching me about your *red coffee mug*. This will take just a few seconds."
- Progress bar with audible ticks; haptic pulse every 25%.
- On completion: success chime + "Done. I learned your *red coffee mug*."

#### Step 5 — Try it now
- Big button: **"Try finding it now"** → goes straight to the scanning screen with that item pre-selected.
- Or **"Save and finish"** → returns to Home.

### 5. Library / My Items

List view (same row style as Home).
- Swipe-actions on each row (works with VoiceOver Custom Actions): **Find**, **Re-train**, **Rename**, **Delete**.
- Tap a row → Item Detail.

### 6. Item Detail

- Big item name at top
- Status: "Trained on *date*, *N* training videos, recognition confidence: high/medium/low"
- A small play-thumbnail strip showing the 4 training clips (each tappable to preview/replay)
- 3 big action buttons: **"Find this item"** · **"Add more training videos"** · **"Delete item"**

### 7. Settings

Sectioned list. Every toggle has a clear spoken value ("Haptics: On").

- **Voice & Speech**: VoiceOver pickup language, speech rate slider, voice gender, verbosity (Concise / Standard / Detailed)
- **Haptics**: Master on/off, intensity slider, "Test haptic"
- **Audio cues**: Sonar style (Ping / Beep / Sine wave / Voice only), stereo panning on/off, found chime selection, volume slider, "Test sound"
- **Camera & Detection**: Sensitivity (Conservative / Balanced / Aggressive), use LiDAR (auto/on/off), low-light boost, max scan time
- **Help**: Replay onboarding, Tutorial videos with audio descriptions, Contact support, Send feedback to developers (one-tap "Shake to report a bug" toggle)
- **Privacy**: "All data is on this device. Tap to learn more." → plain-language explainer
- **About**: Version, credits, open-source licenses

### 8. Quick Help (floating, always available)

A bottom-sheet that opens with contextual tips for the current screen, plus three universal items: **"How to teach an item"**, **"How to find an item"**, **"Contact a sighted helper"** (deep-links to Be My Eyes if installed, or shows phone dialer to a saved emergency contact).

### 9. Error & Edge States

Every state must be designed:
- **No items yet** (empty Library): "You haven't taught me any items yet. Tap *Teach a new item* to start."
- **Camera permission denied**: clear explanation + button to open Settings
- **Scanning timeout (60s no detection)**: "I couldn't find your *red coffee mug* nearby. Want to try a different room or re-train?"
- **Object likely covered/inside something**: "I think it might be hidden. Try opening drawers or moving closer."
- **Low light**: "It's dark here. Tap to turn on the flashlight." (also auto-suggests after 5 sec of low confidence + low light)
- **Battery low while scanning**: warn at 15%, pause and ask at 5%
- **Storage full** (can't save more videos): clear path to delete old item to free space
- **Multiple matches in frame**: spoken "I see two possible matches. Pick the closer one? Tap once for closer, twice for farther."
- **Model failed to train**: friendly error + "Re-record videos" CTA, never a stack trace

---

## VISUAL DESIGN SYSTEM

### Color
Two themes that auto-respect iOS Light/Dark + High Contrast modes:

**Light mode**
- Background: `#FFFFFF`
- Primary text: `#000000` (true black, max contrast)
- Accent (CTAs): `#0040DD` (deep blue, WCAG AAA on white)
- Success: `#005A2B` (dark green)
- Warning: `#A04500`
- Error: `#B00020`

**Dark mode**
- Background: `#000000` (true black, OLED-friendly)
- Primary text: `#FFFFFF`
- Accent: `#4D8BFF`
- Success: `#4ADE80`

**High-contrast variant** (when iOS "Increase Contrast" is on): bump all text/element pairs to ≥ 7:1 contrast ratio.

**Never use color alone to convey meaning.** Pair with icon, text, shape, or texture (per WCAG and Apple HIG).

### Typography
- System font: **SF Pro**, Dynamic Type fully supported (XS → AX5)
- Default body: 17 pt → scales to 53 pt at AX5
- Headline (screen title): 28 pt bold, scales up
- Button label: 22 pt semibold
- Layout must reflow gracefully at AX5 — **stack** instead of inline at large sizes (no truncation, no horizontal overflow)

### Iconography
- SF Symbols **only**, weight: regular or bold
- Always pair with a text label (no icon-only buttons except Settings gear and Close)
- Minimum icon size: 28 pt; scales with Dynamic Type

### Spacing & touch targets
- 8 pt grid
- Minimum touch target: **60×60 pt** (above HIG's 44 pt minimum)
- Minimum spacing between adjacent tappable items: **16 pt**
- Edge insets: 20 pt horizontal on screen edges

### Motion
- Respect **Reduce Motion** — replace slides/parallax with cross-fades
- No essential information conveyed by animation alone
- No flashing > 3 Hz (seizure safety)

---

## ACCESSIBILITY ANNOTATIONS (mandatory per element)

For every screen, annotate every interactive element with:

1. **VoiceOver `accessibilityLabel`** — what the element is, in plain language
2. **VoiceOver `accessibilityHint`** — what happens when activated, starts with a verb ("Opens…", "Starts…")
3. **`accessibilityValue`** — for sliders, toggles, progress (current state)
4. **`accessibilityTraits`** — `.button`, `.header`, `.adjustable`, `.image`, etc.
5. **VoiceOver reading order** — explicitly numbered for non-trivial layouts
6. **Magic Tap behavior** (two-finger double-tap) — what it does on this screen
7. **Escape gesture** (two-finger Z scrub) — what it dismisses
8. **Custom Rotor entries** — e.g., a "Items" rotor on Home for fast list traversal
9. **Haptic and sound cues** that accompany the visual state

### Example annotation block (for the scanning screen Found state)

```
Element: Found banner
  Label: "Found your red coffee mug"
  Hint: "Double tap to hear distance and direction again"
  Value: "About 1 foot ahead, slightly right"
  Traits: .updatesFrequently, .button
  Sound: Success chord (C major arpeggio, 600 ms)
  Haptic: .success notification + 2 sharp taps (CoreHaptics)
  Reading order: 1 of 4 on this screen
  Magic Tap: Re-announce result
```

Apply the same level of detail to every interactive element across every screen.

---

## INTERACTION PATTERNS LIBRARY

Define and use consistently:

- **Sonar feedback model** (proximity → ping rate, pitch, pan): publish the exact mapping curve.
- **Spoken-nudge throttle**: never more than 1 spoken nudge per 3 seconds; haptics can be continuous.
- **VoiceOver-aware tap zones**: when VO is on, the entire camera preview is one accessible element with custom rotor actions ("Repeat", "Describe scene", "Pause", "Stop").
- **One-handed ergonomics**: all primary actions reachable with the right thumb on a 6.7" screen; mirror for left-handed mode.
- **Recovery from misuse**: any destructive action (delete item) requires confirmation with a spoken summary and a 3-second "Undo" toast.

---

## DELIVERABLES (please produce all of these)

1. **App map** — visual sitemap with every screen and the transitions between them
2. **Wireframes for every screen** listed above, **in both light and dark mode**, at:
   - Default Dynamic Type
   - AX1 (200%) Dynamic Type
   - AX5 (310%) Dynamic Type
3. **Hi-fi mockups** for the 8 most critical screens: Home, Find/Item Picker, Scanning, Found, Teach Step 1, Teach Step 3 (recording), Library, Item Detail
4. **Empty states, error states, and loading states** for every screen
5. **A complete component library**: buttons (primary/secondary/destructive/ghost), list rows, sheets, toasts, sliders, toggles, segmented controls, progress, the camera HUD, the sonar visualizer
6. **Accessibility annotation overlays** as described above for every interactive element
7. **An audio + haptic feedback spec sheet**: every cue, when it fires, its sound design notes (frequency, envelope), its haptic pattern (CoreHaptics description)
8. **A VoiceOver script walkthrough** for the two key flows (Teach a new item; Find an item) — write out exactly what VoiceOver speaks at every step, including the user gestures between
9. **A "first 60 seconds" storyboard** — a brand-new blind user opens the app for the first time. Show frame-by-frame what they hear, feel, and tap.
10. **Edge-case design**: no permissions, no items, low light, low battery, model fails, multiple matches, ambiguous match — all explicitly designed
11. **Settings page** with full hierarchy and every option's default value
12. **A short rationale doc** (1–2 pages) explaining *why* the design respects the principles above, with citations to Apple HIG, WCAG AA/AAA, and lessons borrowed from Seeing AI / Be My Eyes / Envision

---

## CONSTRAINTS & DON'TS

- **Don't** rely on color, position, or animation alone for any meaningful information.
- **Don't** auto-dismiss anything important — blind users navigate slower.
- **Don't** use modals stacked more than one deep.
- **Don't** put critical actions in swipe-only gestures without an equivalent button.
- **Don't** use placeholder text as the only label for an input.
- **Don't** design tiny inline icon-only buttons.
- **Don't** assume the user can frame the camera — guide them.
- **Don't** speak over VoiceOver — always pause synthesizer when VO is active and route through proper channels.
- **Don't** require an internet connection for any core flow.
- **Don't** show a tutorial that can't be replayed.

---

## SUCCESS CRITERIA / SELF-CHECK

Before delivering, verify:

- [ ] A totally blind user can complete *teach* and *find* end-to-end with VoiceOver, no sighted assistance, no visual reference.
- [ ] Every screen has a clear, predictable VoiceOver reading order.
- [ ] Every interactive element has label + hint + traits.
- [ ] Every visual cue has an audio AND haptic equivalent.
- [ ] All touch targets ≥ 60×60 pt.
- [ ] All text passes WCAG AA (4.5:1) at minimum, AAA (7:1) where feasible.
- [ ] Layout reflows correctly at AX5 Dynamic Type with no truncation.
- [ ] No flow has a hard timeout shorter than 30 seconds.
- [ ] Every error state is recoverable with a clear path forward.
- [ ] Light mode, Dark mode, and High Contrast variants all designed.
- [ ] The 8 deliverable hi-fi screens look polished enough to ship.

Now produce the design.
