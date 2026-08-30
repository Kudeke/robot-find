// screens-teach.jsx — Teach wizard (5 steps) and Settings/Help

function ScreenTeach({ theme, scale, onCancel, onComplete, presetName }) {
  const t = theme;
  const [step, setStep] = React.useState(1);
  const [name, setName] = React.useState(presetName || '');
  const [clipsRecorded, setClipsRecorded] = React.useState(0);
  const [recording, setRecording] = React.useState(false);
  const [trainProgress, setTrainProgress] = React.useState(0);

  React.useEffect(() => {
    if (step === 4) {
      setTrainProgress(0);
      const id = setInterval(() => {
        setTrainProgress(p => {
          if (p >= 100) { clearInterval(id); return 100; }
          return p + 5;
        });
      }, 140);
      return () => clearInterval(id);
    }
  }, [step]);

  React.useEffect(() => {
    if (recording) {
      const t = setTimeout(() => {
        setRecording(false);
        setClipsRecorded(c => Math.min(4, c + 1));
      }, 1800);
      return () => clearTimeout(t);
    }
  }, [recording]);

  const angles = ['Front view', 'Side view', 'Top view', 'Different background'];
  const totalSteps = 5;

  const stepHeader = (
    <div style={{ padding: '60px 20px 12px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', minHeight: 44 }}>
        <FMTIconButton theme={t} size={48} label={step === 1 ? 'Cancel' : 'Back'} hint={step === 1 ? 'Cancels teaching' : 'Goes back a step'}
          onClick={() => step === 1 ? onCancel() : setStep(step - 1)}>
          {step === 1 ? FMTIcon.close(20, t.text) : FMTIcon.chevL(14, t.text)}
        </FMTIconButton>
        <div style={{ fontFamily: FMT_FONT, fontSize: 15 * scale, fontWeight: 600, color: t.textSecondary }}
          data-fmt-label={`Step ${step} of ${totalSteps}`} data-fmt-trait="header">
          Step {step} of {totalSteps}
        </div>
        <div style={{ width: 48 }}/>
      </div>
      <div style={{ display: 'flex', gap: 4, marginTop: 12 }}>
        {[1, 2, 3, 4, 5].map(n => (
          <div key={n} style={{
            flex: 1, height: 6, borderRadius: 3,
            background: n <= step ? t.accent : t.separator,
          }}/>
        ))}
      </div>
    </div>
  );

  // Step 1: name ─────────────────────────────────────────────────────────
  if (step === 1) {
    const suggestions = ['Keys', 'Wallet', 'White cane', 'Headphones', 'Mug', 'Remote', 'Phone charger', 'Medication'];
    return (
      <div style={{ height: '100%', background: t.bg, color: t.text, display: 'flex', flexDirection: 'column' }}>
        {stepHeader}
        <div style={{ flex: 1, overflowY: 'auto', padding: '12px 20px' }}>
          <h1 style={{ fontFamily: FMT_FONT, fontSize: 30 * scale, fontWeight: 700, color: t.text, letterSpacing: -0.5, lineHeight: 1.1, margin: 0 }} data-fmt-trait="header">Name your item</h1>
          <p style={{ marginTop: 12, fontFamily: FMT_FONT, fontSize: 17 * scale, color: t.textSecondary, lineHeight: 1.4 }}>
            What do you want to call this item? You can dictate by tapping the microphone.
          </p>
          <div style={{ marginTop: 24 }}>
            <label style={{ display: 'block', fontFamily: FMT_FONT, fontSize: 14 * scale, fontWeight: 600, color: t.textSecondary, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 8 }}>
              Item name
            </label>
            <div style={{
              background: t.fieldBg, borderRadius: 16, padding: '18px 18px',
              display: 'flex', alignItems: 'center', gap: 12,
              border: t.isHC ? `2px solid ${t.text}` : `2px solid ${t.accent}`,
            }} data-fmt-label="Item name input" data-fmt-hint="Type or dictate the name of your item" data-fmt-trait="textField">
              <input
                value={name} onChange={e => setName(e.target.value)}
                placeholder="e.g. Red coffee mug"
                style={{
                  flex: 1, border: 'none', outline: 'none', background: 'transparent',
                  fontFamily: FMT_FONT, fontSize: 22 * scale, fontWeight: 600,
                  color: t.text, letterSpacing: -0.3, minWidth: 0,
                }}
              />
              <button style={{ background: 'transparent', border: 'none', cursor: 'pointer', padding: 4 }} data-fmt-label="Dictate" data-fmt-hint="Starts voice input" data-fmt-trait="button">
                {FMTIcon.mic(28 * scale, t.accent)}
              </button>
            </div>
          </div>

          <div style={{ marginTop: 28 }}>
            <div style={{ fontFamily: FMT_FONT, fontSize: 14 * scale, fontWeight: 600, color: t.textSecondary, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 12 }}>
              Suggestions
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10 }}>
              {suggestions.map(s => (
                <button key={s} onClick={() => setName(s)} style={{
                  minHeight: 44, padding: '10px 16px', borderRadius: 999,
                  background: t.chipBg, color: t.chipText, border: t.isHC ? `2px solid ${t.text}` : 'none',
                  fontFamily: FMT_FONT, fontSize: 16 * scale, fontWeight: 600, cursor: 'pointer',
                }} data-fmt-label={`Suggestion: ${s}`} data-fmt-hint={`Sets the name to ${s}`} data-fmt-trait="button">
                  {s}
                </button>
              ))}
            </div>
          </div>
        </div>
        <div style={{ padding: '12px 20px 28px' }}>
          <FMTButton theme={t} scale={scale} variant="primary" label="Next"
            icon={FMTIcon.arrowR(22 * scale, t.onAccent)}
            ariaHint="Goes to setup, step 2 of 5"
            onClick={() => name && setStep(2)} height={68 * Math.max(1, scale * 0.85)}/>
        </div>
      </div>
    );
  }

  // Step 2: setup ────────────────────────────────────────────────────────
  if (step === 2) {
    return (
      <div style={{ height: '100%', background: t.bg, color: t.text, display: 'flex', flexDirection: 'column' }}>
        {stepHeader}
        <div style={{ flex: 1, overflowY: 'auto', padding: '12px 20px' }}>
          <h1 style={{ fontFamily: FMT_FONT, fontSize: 30 * scale, fontWeight: 700, color: t.text, letterSpacing: -0.5, lineHeight: 1.1, margin: 0 }} data-fmt-trait="header">Get ready</h1>
          <p style={{ marginTop: 12, fontFamily: FMT_FONT, fontSize: 19 * scale, color: t.textSecondary, lineHeight: 1.4 }}>
            Place <strong style={{ color: t.text }}>{name || 'your item'}</strong> on a flat surface in good lighting. Make sure nothing else cluttered is around it. Tell me when you're ready.
          </p>

          <div style={{ marginTop: 24, padding: 20, borderRadius: 18, background: t.surface, border: t.isHC ? `2px solid ${t.text}` : 'none' }}>
            <div style={{ fontFamily: FMT_FONT, fontSize: 14 * scale, fontWeight: 700, color: t.text, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 12 }}>Tips</div>
            <ul style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 14 }}>
              {[
                'Use a contrasting background — a plain table works well.',
                'Hold the phone about one foot away.',
                'You\u2019ll record 4 short videos from different angles.',
                'Each video is about 5 seconds.',
              ].map((tip, i) => (
                <li key={i} style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
                  <div style={{ width: 24, height: 24, borderRadius: 12, background: t.successBg, color: t.success, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, border: t.isHC ? `1.5px solid ${t.text}` : 'none' }}>
                    {FMTIcon.check(14, t.success)}
                  </div>
                  <span style={{ fontFamily: FMT_FONT, fontSize: 16 * scale, color: t.text, lineHeight: 1.4 }}>{tip}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
        <div style={{ padding: '12px 20px 28px', display: 'flex', flexDirection: 'column', gap: 10 }}>
          <FMTButton theme={t} scale={scale} variant="primary" label="I'm ready"
            ariaHint="Starts video recording, step 3 of 5"
            onClick={() => setStep(3)} height={68 * Math.max(1, scale * 0.85)}/>
          <FMTButton theme={t} scale={scale} variant="ghost" label="Get help framing"
            ariaHint="Uses the camera to verify the item is centered with audio guidance"
            onClick={() => setStep(3)}/>
        </div>
      </div>
    );
  }

  // Step 3: record 4 clips ──────────────────────────────────────────────
  if (step === 3) {
    const angle = angles[Math.min(clipsRecorded, 3)];
    const done = clipsRecorded >= 4;
    return (
      <div style={{ height: '100%', background: '#000', color: '#fff', display: 'flex', flexDirection: 'column' }}>
        {stepHeader}
        <div style={{ padding: '12px 20px', textAlign: 'center' }}>
          <div style={{ fontFamily: FMT_FONT, fontSize: 14 * scale, fontWeight: 600, color: 'rgba(255,255,255,0.7)', textTransform: 'uppercase', letterSpacing: 0.5 }}>
            Video {Math.min(clipsRecorded + 1, 4)} of 4
          </div>
          <div style={{ marginTop: 6, fontFamily: FMT_FONT, fontSize: 28 * scale, fontWeight: 700, letterSpacing: -0.4 }} data-fmt-trait="header">
            {done ? 'All 4 videos recorded' : angle}
          </div>
        </div>

        {/* Mock camera viewfinder */}
        <div style={{ flex: 1, margin: '0 20px', borderRadius: 24, position: 'relative', overflow: 'hidden',
          background: 'radial-gradient(circle at 50% 40%, #2a2a30 0%, #0a0a0c 75%)',
          border: t.isHC ? `2px solid ${t.accent}` : 'none' }}>
          {/* placeholder item */}
          <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <div style={{
              width: 130, height: 130, borderRadius: 28,
              background: `linear-gradient(135deg, ${FMT_ITEM_SWATCHES.mug[0]}, ${FMT_ITEM_SWATCHES.mug[1]})`,
              boxShadow: '0 20px 60px rgba(0,0,0,0.5)',
              transform: `rotate(${clipsRecorded * 22}deg)`,
              transition: 'transform 400ms',
              backgroundImage: 'repeating-linear-gradient(45deg, rgba(255,255,255,0.1) 0 6px, transparent 6px 12px)',
            }}/>
          </div>
          {/* framing brackets */}
          {['tl','tr','bl','br'].map(corner => {
            const styles = {
              tl: { top: 24, left: 24, borderTop: '3px solid #FFD60A', borderLeft: '3px solid #FFD60A' },
              tr: { top: 24, right: 24, borderTop: '3px solid #FFD60A', borderRight: '3px solid #FFD60A' },
              bl: { bottom: 24, left: 24, borderBottom: '3px solid #FFD60A', borderLeft: '3px solid #FFD60A' },
              br: { bottom: 24, right: 24, borderBottom: '3px solid #FFD60A', borderRight: '3px solid #FFD60A' },
            }[corner];
            const radii = { tl: { borderTopLeftRadius: 8 }, tr: { borderTopRightRadius: 8 }, bl: { borderBottomLeftRadius: 8 }, br: { borderBottomRightRadius: 8 } }[corner];
            return <div key={corner} style={{ position: 'absolute', width: 36, height: 36, ...styles, ...radii }}/>;
          })}
          {/* recording indicator */}
          {recording && (
            <div style={{ position: 'absolute', top: 20, left: '50%', transform: 'translateX(-50%)',
              padding: '6px 14px', borderRadius: 999, background: 'rgba(255,59,48,0.9)',
              fontFamily: FMT_FONT, fontSize: 14, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 8 }}>
              <span style={{ width: 8, height: 8, borderRadius: 4, background: '#fff', animation: 'fmtPulse 1s infinite' }}/>
              REC
            </div>
          )}
          {/* live coaching */}
          <div style={{
            position: 'absolute', bottom: 16, left: 16, right: 16, padding: '12px 16px',
            background: 'rgba(0,0,0,0.55)', backdropFilter: 'blur(20px)', borderRadius: 14,
            fontFamily: FMT_FONT, fontSize: 15 * scale, color: '#fff', textAlign: 'center',
          }} data-fmt-label={recording ? 'Live coaching: Good, keep going' : 'Live coaching: Hold the phone about one foot away'} data-fmt-trait="updatesFrequently">
            {recording ? '✓ Good, keep going. Move slowly.' : 'Hold the phone about one foot away.'}
          </div>
        </div>

        {/* clip indicators */}
        <div style={{ padding: '16px 20px 8px', display: 'flex', gap: 8, justifyContent: 'center' }}>
          {[0,1,2,3].map(i => (
            <div key={i} style={{
              flex: 1, maxWidth: 60, height: 6, borderRadius: 3,
              background: i < clipsRecorded ? '#34C759' : 'rgba(255,255,255,0.18)',
            }}/>
          ))}
        </div>

        <div style={{ padding: '8px 20px 28px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
          <button
            onClick={() => !recording && !done && setRecording(true)}
            data-fmt-label={done ? 'All videos recorded' : `Record video ${clipsRecorded + 1} of 4`}
            data-fmt-hint={done ? '' : 'Tap to record. Tap and hold to redo the previous video.'}
            data-fmt-trait="button"
            disabled={done}
            style={{
              width: 96, height: 96, borderRadius: 48,
              background: '#fff', border: '4px solid rgba(255,255,255,0.4)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              cursor: done ? 'default' : 'pointer', opacity: done ? 0.4 : 1,
            }}
          >
            <div style={{
              width: recording ? 32 : 76, height: recording ? 32 : 76,
              borderRadius: recording ? 6 : 38, background: '#FF3B30', transition: 'all 200ms',
            }}/>
          </button>
          <div style={{ fontFamily: FMT_FONT, fontSize: 16 * scale, color: 'rgba(255,255,255,0.7)' }}>
            {done ? 'Tap Next to train the model' : (recording ? 'Recording…' : 'Tap to record')}
          </div>
          <FMTButton theme={t} scale={scale} variant="primary" label={done ? 'Train now' : 'Next'}
            ariaHint={done ? 'Trains the model on your videos, step 4 of 5' : 'Continues to training when all 4 clips are recorded'}
            onClick={() => done && setStep(4)} height={60} fullWidth/>
        </div>
        <style>{`@keyframes fmtPulse { 0%,100%{opacity:1} 50%{opacity:0.3} }`}</style>
      </div>
    );
  }

  // Step 4: training ─────────────────────────────────────────────────────
  if (step === 4) {
    const done = trainProgress >= 100;
    return (
      <div style={{ height: '100%', background: t.bg, color: t.text, display: 'flex', flexDirection: 'column' }}>
        {stepHeader}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '20px 28px', textAlign: 'center', gap: 28 }}>
          {/* progress ring */}
          <div style={{ position: 'relative', width: 200, height: 200 }} data-fmt-label={`Training, ${trainProgress} percent complete`} data-fmt-trait="updatesFrequently">
            <svg width="200" height="200" viewBox="0 0 200 200">
              <circle cx="100" cy="100" r="88" stroke={t.separator} strokeWidth="10" fill="none"/>
              <circle cx="100" cy="100" r="88"
                stroke={done ? t.success : t.accent} strokeWidth="10" fill="none"
                strokeLinecap="round"
                strokeDasharray={2 * Math.PI * 88}
                strokeDashoffset={2 * Math.PI * 88 * (1 - trainProgress / 100)}
                transform="rotate(-90 100 100)"
                style={{ transition: 'stroke-dashoffset 200ms' }}/>
            </svg>
            <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: FMT_FONT, fontSize: 56, fontWeight: 700, color: t.text, letterSpacing: -1.5 }}>
              {done ? FMTIcon.check(56, t.success) : `${trainProgress}%`}
            </div>
          </div>
          <div>
            <h1 style={{ fontFamily: FMT_FONT, fontSize: 28 * scale, fontWeight: 700, color: t.text, letterSpacing: -0.4, margin: 0 }} data-fmt-trait="header">
              {done ? 'Done!' : 'Teaching me…'}
            </h1>
            <p style={{ marginTop: 10, fontFamily: FMT_FONT, fontSize: 19 * scale, color: t.textSecondary, lineHeight: 1.4 }}>
              {done ? `I learned your ${name || 'item'}.` : `Teaching me about your ${name || 'item'}. This will take just a few seconds.`}
            </p>
          </div>
        </div>
        <div style={{ padding: '12px 20px 28px' }}>
          <FMTButton theme={t} scale={scale} variant="primary" label="Continue"
            ariaHint="Goes to the final step"
            onClick={() => done && setStep(5)}
            height={68 * Math.max(1, scale * 0.85)}/>
        </div>
      </div>
    );
  }

  // Step 5: try it now ──────────────────────────────────────────────────
  return (
    <div style={{ height: '100%', background: t.bg, color: t.text, display: 'flex', flexDirection: 'column' }}>
      {stepHeader}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '20px 28px', textAlign: 'center', gap: 24 }}>
        <div style={{
          width: 140, height: 140, borderRadius: 70,
          background: t.successBg, color: t.success,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          border: t.isHC ? `3px solid ${t.success}` : 'none',
        }}>
          {FMTIcon.check(72, t.success)}
        </div>
        <div>
          <h1 style={{ fontFamily: FMT_FONT, fontSize: 30 * scale, fontWeight: 700, letterSpacing: -0.5, margin: 0, color: t.text }} data-fmt-trait="header">
            All set
          </h1>
          <p style={{ marginTop: 12, fontFamily: FMT_FONT, fontSize: 19 * scale, color: t.textSecondary, lineHeight: 1.4 }}>
            I can now find your <strong style={{ color: t.text }}>{name || 'item'}</strong>. Want to try it?
          </p>
        </div>
      </div>
      <div style={{ padding: '12px 20px 28px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        <FMTButton theme={t} scale={scale} variant="primary" label="Try finding it now"
          icon={FMTIcon.magnifier(22 * scale, t.onAccent)}
          ariaHint="Goes to scanning with this item selected"
          onClick={() => onComplete({ name: name || 'New item', tryFind: true })}
          height={68 * Math.max(1, scale * 0.85)}/>
        <FMTButton theme={t} scale={scale} variant="secondary" label="Save and finish"
          ariaHint="Saves the item and returns Home"
          onClick={() => onComplete({ name: name || 'New item', tryFind: false })}/>
      </div>
    </div>
  );
}

// Settings ────────────────────────────────────────────────────────────────
function ScreenSettings({ theme, scale, onBack, tweaks, setTweak }) {
  const t = theme;
  const sect = (title, rows) => (
    <div style={{ marginTop: 24 }}>
      <div style={{ padding: '0 28px 8px', fontFamily: FMT_FONT, fontSize: 13 * scale, fontWeight: 600, color: t.textSecondary, textTransform: 'uppercase', letterSpacing: 0.5 }}>{title}</div>
      <div style={{ margin: '0 16px', borderRadius: 18, background: t.surface, border: t.isHC ? `2px solid ${t.text}` : 'none', overflow: 'hidden' }}>
        {rows.map((r, i) => (
          <div key={i} style={{
            minHeight: 56, padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 12,
            borderBottom: i < rows.length - 1 ? `0.5px solid ${t.separator}` : 'none',
          }}
            data-fmt-label={`${r.label}, ${r.value}`}
            data-fmt-hint={r.hint}
            data-fmt-trait={r.trait || 'button'}>
            <div style={{ flex: 1, fontFamily: FMT_FONT, fontSize: 17 * scale, color: t.text }}>{r.label}</div>
            <div style={{ fontFamily: FMT_FONT, fontSize: 16 * scale, color: t.textSecondary }}>{r.value}</div>
            {r.toggle !== undefined ? <Toggle on={r.toggle} theme={t} onChange={r.onChange}/> : FMTIcon.chevR(14, t.textTertiary)}
          </div>
        ))}
      </div>
    </div>
  );

  return (
    <div style={{ height: '100%', overflowY: 'auto', background: t.bgGrouped, color: t.text, paddingTop: 60, paddingBottom: 40 }}>
      <FMTHeader theme={t} scale={scale} title="Settings"
        leading={<FMTIconButton theme={t} size={44} label="Done" hint="Closes settings" onClick={onBack}>{FMTIcon.chevL(14, t.text)}</FMTIconButton>}/>
      {sect('Voice & Speech', [
        { label: 'Verbosity', value: tweaks.verbosity, hint: 'Changes how much VoiceOver says' },
        { label: 'Speech rate', value: 'Normal', hint: 'Adjusts the speed of spoken guidance' },
        { label: 'Verbosity', value: 'Standard', hint: 'Picks the spoken voice' },
      ])}
      {sect('Haptics', [
        { label: 'Haptic feedback', value: tweaks.haptics ? 'On' : 'Off', toggle: tweaks.haptics, onChange: v => setTweak('haptics', v), trait: 'switch', hint: 'Turns vibration cues on or off' },
        { label: 'Intensity', value: 'Strong', hint: 'Adjusts how strong vibrations feel' },
        { label: 'Test haptic', value: '', hint: 'Plays a sample vibration' },
      ])}
      {sect('Audio cues', [
        { label: 'Sonar style', value: 'Ping', hint: 'Pick the audio style for proximity feedback' },
        { label: 'Stereo panning', value: 'On', toggle: true, trait: 'switch', hint: 'Pans audio left or right to indicate direction' },
        { label: 'Found chime', value: 'Chord', hint: 'Sound played when an item is found' },
        { label: 'Volume', value: '80%', trait: 'adjustable', hint: 'Adjusts cue volume' },
      ])}
      {sect('Camera & Detection', [
        { label: 'Sensitivity', value: 'Balanced', hint: 'Conservative finds fewer false matches' },
        { label: 'Use LiDAR', value: 'Auto', hint: 'Use LiDAR for distance when available' },
        { label: 'Low-light boost', value: 'On', toggle: true, trait: 'switch', hint: 'Brightens the preview in dark environments' },
        { label: 'Max scan time', value: '60 seconds', hint: 'How long to scan before giving up' },
      ])}
      {sect('Privacy & Help', [
        { label: 'All data is on this device', value: '', hint: 'Learn what stays on your phone' },
        { label: 'Replay onboarding', value: '', hint: 'Plays the introduction again' },
        { label: 'Tutorial videos', value: '', hint: 'Watch audio-described tutorials' },
        { label: 'Send feedback', value: '', hint: 'Contact the developers' },
      ])}
      <div style={{ padding: '32px 28px 40px', textAlign: 'center', fontFamily: FMT_FONT, fontSize: 13 * scale, color: t.textTertiary }}>
        Find My Things • v1.0
      </div>
    </div>
  );
}

function Toggle({ on, onChange, theme }) {
  const t = theme;
  return (
    <button onClick={() => onChange && onChange(!on)} style={{
      width: 51, height: 31, borderRadius: 16,
      background: on ? (t.isHC ? t.accent : '#34C759') : '#787880',
      border: t.isHC && !on ? `2px solid ${t.text}` : 'none',
      position: 'relative', cursor: 'pointer', flexShrink: 0,
      transition: 'background 200ms',
    }} data-fmt-trait="switch">
      <div style={{
        position: 'absolute', top: 2, left: on ? 22 : 2,
        width: 27, height: 27, borderRadius: 14, background: '#fff',
        boxShadow: '0 2px 4px rgba(0,0,0,0.2)', transition: 'left 200ms',
      }}/>
    </button>
  );
}

// Help sheet ──────────────────────────────────────────────────────────────
function ScreenHelp({ theme, scale, onClose }) {
  const t = theme;
  return (
    <div style={{ height: '100%', background: t.bg, color: t.text, display: 'flex', flexDirection: 'column' }}>
      <div style={{ padding: '60px 20px 12px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div style={{ width: 48 }}/>
        <div style={{ width: 36, height: 5, borderRadius: 3, background: t.separator }}/>
        <FMTIconButton theme={t} size={48} label="Close help" hint="Closes the help sheet" onClick={onClose}>
          {FMTIcon.close(20, t.text)}
        </FMTIconButton>
      </div>
      <div style={{ padding: '12px 20px 24px', flex: 1, overflowY: 'auto' }}>
        <h1 style={{ fontFamily: FMT_FONT, fontSize: 32 * scale, fontWeight: 700, letterSpacing: -0.5, margin: 0, color: t.text }} data-fmt-trait="header">Quick help</h1>
        <p style={{ marginTop: 8, fontFamily: FMT_FONT, fontSize: 17 * scale, color: t.textSecondary }}>Always one tap away.</p>
        <div style={{ marginTop: 20, display: 'flex', flexDirection: 'column', gap: 12 }}>
          {[
            { t: 'How to teach an item', h: '5 steps, about 2 minutes', icon: FMTIcon.plus(24, t.accent) },
            { t: 'How to find an item', h: 'Sounds and vibrations guide you', icon: FMTIcon.magnifier(24, t.accent) },
            { t: 'Contact a sighted helper', h: 'Opens Be My Eyes if installed', icon: FMTIcon.hand(24, t.accent) },
            { t: 'Replay onboarding', h: 'See the introduction again', icon: FMTIcon.waveform(24, t.accent) },
          ].map(r => (
            <button key={r.t} style={{
              width: '100%', minHeight: 76, padding: 16, borderRadius: 18,
              background: t.surface, border: t.isHC ? `2px solid ${t.text}` : 'none',
              display: 'flex', alignItems: 'center', gap: 14, cursor: 'pointer', textAlign: 'left',
            }} data-fmt-label={r.t} data-fmt-hint={r.h} data-fmt-trait="button">
              <div style={{ width: 44, height: 44, borderRadius: 12, background: t.chipBg, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                {r.icon}
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontFamily: FMT_FONT, fontSize: 19 * scale, fontWeight: 600, color: t.text }}>{r.t}</div>
                <div style={{ marginTop: 2, fontFamily: FMT_FONT, fontSize: 15 * scale, color: t.textSecondary }}>{r.h}</div>
              </div>
              {FMTIcon.chevR(14, t.textTertiary)}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenTeach, ScreenSettings, ScreenHelp, Toggle });
