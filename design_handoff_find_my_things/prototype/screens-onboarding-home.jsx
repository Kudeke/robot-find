// screens-onboarding-home.jsx — Onboarding, Home, Library

const ITEMS_SEED = [
  { id: 'keys', name: 'House keys', kind: 'keys', status: 'ready', lastUsed: 'Today, 9:12 AM', confidence: 'high', trainedOn: 'Apr 22, 2026', clips: 4 },
  { id: 'mug', name: 'Red coffee mug', kind: 'mug', status: 'ready', lastUsed: 'Yesterday', confidence: 'high', trainedOn: 'Apr 14, 2026', clips: 4 },
  { id: 'cane', name: 'White cane', kind: 'cane', status: 'ready', lastUsed: '2 days ago', confidence: 'high', trainedOn: 'Apr 02, 2026', clips: 4 },
  { id: 'headphones', name: 'AirPods case', kind: 'headphones', status: 'ready', lastUsed: '3 days ago', confidence: 'medium', trainedOn: 'Mar 28, 2026', clips: 4 },
  { id: 'wallet', name: 'Brown wallet', kind: 'wallet', status: 'needs', lastUsed: 'Last week', confidence: 'low', trainedOn: 'Mar 14, 2026', clips: 2 },
  { id: 'remote', name: 'TV remote', kind: 'remote', status: 'ready', lastUsed: 'Last week', confidence: 'medium', trainedOn: 'Mar 12, 2026', clips: 4 },
  { id: 'meds', name: 'Morning medication', kind: 'meds', status: 'ready', lastUsed: '2 weeks ago', confidence: 'high', trainedOn: 'Mar 01, 2026', clips: 4 },
];

// Onboarding ────────────────────────────────────────────────────────────────
function ScreenOnboarding({ theme, scale, onDone }) {
  const t = theme;
  const [step, setStep] = React.useState(0);
  const slides = [
    { h: 'Teach me your things.', b: 'Record 4 short videos of an object — your keys, mug, anything. I\u2019ll learn what it looks like.', glyph: 'teach' },
    { h: 'I\u2019ll help you find them.', b: 'Point your phone around. I\u2019ll guide you with sounds and vibrations until the object is in reach.', glyph: 'find' },
    { h: 'Everything stays on your iPhone.', b: 'Your videos and the AI model never leave your device.', glyph: 'lock' },
  ];
  const s = slides[step];
  const Glyph = () => {
    const c = t.accent;
    if (s.glyph === 'teach') return (
      <svg width="160" height="160" viewBox="0 0 160 160" fill="none">
        <circle cx="80" cy="80" r="76" stroke={c} strokeWidth="3" opacity="0.25"/>
        <rect x="42" y="56" width="76" height="58" rx="10" stroke={c} strokeWidth="4"/>
        <circle cx="80" cy="85" r="14" stroke={c} strokeWidth="4"/>
        <circle cx="80" cy="85" r="6" fill={c}/>
        <rect x="64" y="44" width="32" height="14" rx="4" stroke={c} strokeWidth="4"/>
      </svg>
    );
    if (s.glyph === 'find') return (
      <svg width="160" height="160" viewBox="0 0 160 160" fill="none">
        <circle cx="80" cy="80" r="20" stroke={c} strokeWidth="4"/>
        <circle cx="80" cy="80" r="40" stroke={c} strokeWidth="3" opacity="0.55"/>
        <circle cx="80" cy="80" r="60" stroke={c} strokeWidth="3" opacity="0.3"/>
        <circle cx="80" cy="80" r="76" stroke={c} strokeWidth="3" opacity="0.15"/>
        <circle cx="80" cy="80" r="6" fill={c}/>
      </svg>
    );
    return (
      <svg width="160" height="160" viewBox="0 0 160 160" fill="none">
        <rect x="40" y="68" width="80" height="62" rx="14" stroke={c} strokeWidth="4"/>
        <path d="M58 68V52a22 22 0 0144 0v16" stroke={c} strokeWidth="4"/>
        <circle cx="80" cy="98" r="6" fill={c}/>
        <path d="M80 104v8" stroke={c} strokeWidth="4" strokeLinecap="round"/>
      </svg>
    );
  };

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', background: t.bg, color: t.text, paddingTop: 60, paddingBottom: 34 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 20px' }}>
        <div style={{ display: 'flex', gap: 6 }}>
          {slides.map((_, i) => (
            <div key={i} style={{
              width: i === step ? 28 : 8, height: 8, borderRadius: 4,
              background: i === step ? t.accent : t.separator, transition: 'width 200ms',
            }}/>
          ))}
        </div>
        <button onClick={onDone} style={{
          minWidth: 60, minHeight: 44, padding: '10px 16px', background: 'transparent',
          border: 'none', color: t.accent, fontFamily: FMT_FONT, fontSize: 17 * scale, fontWeight: 600, cursor: 'pointer',
        }} data-fmt-label="Skip onboarding" data-fmt-hint="Skips the introduction and goes to Home" data-fmt-trait="button">
          Skip
        </button>
      </div>

      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '0 28px', textAlign: 'center', gap: 24 }}>
        <div style={{ display: 'flex', justifyContent: 'center' }}><Glyph/></div>
        <div>
          <div style={{
            fontFamily: FMT_FONT, fontWeight: 700, fontSize: 32 * scale,
            color: t.text, letterSpacing: -0.6, lineHeight: 1.1, textWrap: 'balance',
          }} data-fmt-label={s.h} data-fmt-trait="header">{s.h}</div>
          <div style={{
            marginTop: 16, fontFamily: FMT_FONT, fontSize: 19 * scale,
            color: t.textSecondary, lineHeight: 1.4, textWrap: 'pretty',
          }}>{s.b}</div>
        </div>
      </div>

      <FMTSection>
        <FMTButton
          theme={t} scale={scale}
          variant="primary"
          height={72 * Math.max(1, scale * 0.9)}
          label={step < slides.length - 1 ? 'Continue' : 'Start'}
          ariaHint={step < slides.length - 1 ? 'Goes to the next slide' : 'Finishes onboarding and opens Home'}
          onClick={() => step < slides.length - 1 ? setStep(step + 1) : onDone()}
        />
        {step > 0 && (
          <button onClick={() => setStep(step - 1)} style={{
            minHeight: 44, padding: 12, background: 'transparent', border: 'none',
            color: t.accent, fontFamily: FMT_FONT, fontSize: 17 * scale, fontWeight: 500, cursor: 'pointer',
          }} data-fmt-label="Back" data-fmt-hint="Goes to the previous slide" data-fmt-trait="button">Back</button>
        )}
      </FMTSection>
    </div>
  );
}

// Home ──────────────────────────────────────────────────────────────────────
function ScreenHome({ theme, scale, onFind, onTeach, onItem, onSettings, onHelp, items, voOn }) {
  const t = theme;
  const greeting = `Hello. You have ${items.length} items saved.`;
  return (
    <div style={{ height: '100%', overflowY: 'auto', background: t.bg, color: t.text, paddingTop: 60, paddingBottom: 100 }}>
      <FMTHeader
        theme={t} scale={scale}
        title="Find My Things"
        subtitle={greeting}
        leading={null}
        trailing={
          <FMTIconButton theme={t} size={48} label="Settings" hint="Opens app settings"
            onClick={onSettings}>
            {FMTIcon.gear(24, t.text)}
          </FMTIconButton>
        }
      />

      <div style={{ height: 16 }}/>

      <FMTSection gap={12}>
        <FMTButton
          theme={t} scale={scale} variant="primary"
          height={96 * Math.max(1, scale * 0.85)}
          label="Find an item"
          sublabel="Scan with the camera"
          icon={FMTIcon.magnifier(28 * scale, t.onAccent)}
          ariaHint="Opens a list of your items so you can pick one to find"
          onClick={onFind}
        />
        <FMTButton
          theme={t} scale={scale} variant="secondary"
          height={96 * Math.max(1, scale * 0.85)}
          label="Teach a new item"
          sublabel="Record 4 short videos"
          icon={FMTIcon.plus(28 * scale, t.isHC ? t.text : t.accent)}
          ariaHint="Starts the 5-step Teach wizard"
          onClick={onTeach}
        />
      </FMTSection>

      <div style={{ padding: '32px 20px 12px', display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <h2 style={{
          fontFamily: FMT_FONT, fontSize: 22 * scale, fontWeight: 700,
          color: t.text, letterSpacing: -0.4, margin: 0,
        }} data-fmt-label="My items, heading" data-fmt-trait="header">My items</h2>
        <div style={{ fontFamily: FMT_FONT, fontSize: 15 * scale, color: t.textSecondary }}>
          {items.length} saved
        </div>
      </div>

      <div style={{ padding: '0 20px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {items.map((it, i) => (
          <ItemRow key={it.id} item={it} theme={t} scale={scale} onClick={() => onItem(it)} voOn={voOn} index={i + 5}/>
        ))}
      </div>

      <div style={{ height: 24 }}/>

      <div style={{ padding: '0 20px' }}>
        <button onClick={onHelp} style={{
          width: '100%', minHeight: 60, borderRadius: 18,
          background: 'transparent', border: `1.5px dashed ${t.separator}`,
          color: t.textSecondary, fontFamily: FMT_FONT, fontSize: 16 * scale, fontWeight: 500,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10, cursor: 'pointer',
        }} data-fmt-label="Quick help" data-fmt-hint="Opens contextual help and tutorials" data-fmt-trait="button">
          {FMTIcon.questionCircle(22 * scale, t.textSecondary)} Quick help
        </button>
      </div>
    </div>
  );
}

function ItemRow({ item, theme, scale, onClick, voOn, index }) {
  const t = theme;
  const statusColor = item.status === 'ready' ? t.success : t.warning;
  const statusBg = item.status === 'ready' ? t.successBg : (t.isDark ? 'rgba(255,169,77,0.18)' : '#FFF1E0');
  return (
    <button
      onClick={onClick}
      data-fmt-label={`${item.name}. ${item.status === 'ready' ? 'Ready' : 'Needs more training'}. Last used ${item.lastUsed}.`}
      data-fmt-hint="Opens item details"
      data-fmt-trait="button"
      data-fmt-order={index}
      style={{
        width: '100%', minHeight: 80, borderRadius: 18,
        background: t.surface, border: t.isHC ? `2px solid ${t.text}` : 'none',
        padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 14,
        cursor: 'pointer', textAlign: 'left',
        boxShadow: t.isDark || t.isHC ? 'none' : '0 1px 0 rgba(0,0,0,0.03)',
      }}
    >
      <FMTItemThumb kind={item.kind} size={56} theme={t}/>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontFamily: FMT_FONT, fontSize: 22 * scale, fontWeight: 700,
          color: t.text, letterSpacing: -0.3, lineHeight: 1.15,
          overflow: 'hidden', textOverflow: 'ellipsis',
        }}>{item.name}</div>
        <div style={{ marginTop: 6, display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            fontFamily: FMT_FONT, fontSize: 13 * scale, fontWeight: 600,
            color: statusColor, background: statusBg, padding: '3px 10px', borderRadius: 999,
            border: t.isHC ? `1.5px solid ${t.text}` : 'none',
          }}>
            <span style={{ width: 6, height: 6, borderRadius: 3, background: statusColor }}/>
            {item.status === 'ready' ? 'Ready' : 'Needs training'}
          </span>
          <span style={{ fontFamily: FMT_FONT, fontSize: 14 * scale, color: t.textSecondary }}>
            {item.lastUsed}
          </span>
        </div>
      </div>
      <div style={{ flexShrink: 0, color: t.textTertiary }}>{FMTIcon.chevR(14 * scale, t.textTertiary)}</div>
    </button>
  );
}

// Library (same data, different framing) ────────────────────────────────────
function ScreenLibrary({ theme, scale, items, onBack, onItem, onTeach, voOn }) {
  const t = theme;
  return (
    <div style={{ height: '100%', overflowY: 'auto', background: t.bgGrouped, color: t.text, paddingTop: 60, paddingBottom: 110 }}>
      <FMTHeader theme={t} scale={scale} title="Library" subtitle={`${items.length} items, all on this device.`}
        leading={
          <FMTIconButton theme={t} size={44} label="Back" hint="Goes back to Home" onClick={onBack}>
            {FMTIcon.chevL(14, t.text)}
          </FMTIconButton>
        }
        trailing={
          <FMTIconButton theme={t} size={44} label="Teach a new item" hint="Starts adding a new item" onClick={onTeach}>
            {FMTIcon.plus(22, t.text)}
          </FMTIconButton>
        }
      />
      <div style={{ padding: '8px 20px' }}>
        <div style={{
          background: t.fieldBg, borderRadius: 14, padding: '14px 16px',
          fontFamily: FMT_FONT, fontSize: 17 * scale, color: t.textSecondary,
          display: 'flex', alignItems: 'center', gap: 10,
          border: t.isHC ? `2px solid ${t.text}` : 'none',
        }}
          data-fmt-label="Search items" data-fmt-hint="Type or dictate to search your items" data-fmt-trait="searchField">
          {FMTIcon.magnifier(20 * scale, t.textSecondary)}
          <span>Search items</span>
          <div style={{ flex: 1 }}/>
          {FMTIcon.mic(22 * scale, t.accent)}
        </div>
      </div>
      <div style={{ padding: '12px 20px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {items.map((it, i) => (
          <ItemRow key={it.id} item={it} theme={t} scale={scale} onClick={() => onItem(it)} voOn={voOn} index={i + 3}/>
        ))}
      </div>
    </div>
  );
}

// Item Detail ───────────────────────────────────────────────────────────────
function ScreenItemDetail({ theme, scale, item, onBack, onFind, onRetrain, onDelete }) {
  const t = theme;
  const conf = item.confidence;
  const confColor = conf === 'high' ? t.success : conf === 'medium' ? t.warning : t.error;
  return (
    <div style={{ height: '100%', overflowY: 'auto', background: t.bgGrouped, color: t.text, paddingTop: 60, paddingBottom: 40 }}>
      <FMTHeader theme={t} scale={scale} title={item.name}
        subtitle={`Trained ${item.trainedOn} • ${item.clips} videos`}
        leading={
          <FMTIconButton theme={t} size={44} label="Back" hint="Goes back to Library" onClick={onBack}>
            {FMTIcon.chevL(14, t.text)}
          </FMTIconButton>
        }
      />

      <div style={{ padding: '8px 20px' }}>
        <div style={{
          background: t.surface, borderRadius: 22, padding: 20,
          display: 'flex', alignItems: 'center', gap: 18,
          border: t.isHC ? `2px solid ${t.text}` : 'none',
        }}>
          <FMTItemThumb kind={item.kind} size={88 * Math.max(1, scale * 0.9)} theme={t}/>
          <div style={{ flex: 1 }}>
            <div style={{ fontFamily: FMT_FONT, fontSize: 14 * scale, color: t.textSecondary, fontWeight: 500, textTransform: 'uppercase', letterSpacing: 0.5 }}>Recognition</div>
            <div style={{ marginTop: 4, fontFamily: FMT_FONT, fontSize: 24 * scale, fontWeight: 700, color: confColor, letterSpacing: -0.3 }}>
              {conf === 'high' ? 'High confidence' : conf === 'medium' ? 'Medium' : 'Low — re-train'}
            </div>
          </div>
        </div>
      </div>

      <div style={{ padding: '24px 20px 12px' }}>
        <div style={{
          fontFamily: FMT_FONT, fontSize: 13 * scale, fontWeight: 600,
          color: t.textSecondary, textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 12,
        }} data-fmt-trait="header">Training videos</div>
        <div style={{ display: 'flex', gap: 10, overflowX: 'auto', paddingBottom: 4 }}>
          {[1, 2, 3, 4].map(n => (
            <div key={n} style={{
              flexShrink: 0, width: 110, height: 150, borderRadius: 14,
              background: `linear-gradient(135deg, ${FMT_ITEM_SWATCHES[item.kind][0]}, ${FMT_ITEM_SWATCHES[item.kind][1]})`,
              position: 'relative', overflow: 'hidden',
              border: t.isHC ? `2px solid ${t.text}` : 'none',
            }}
              data-fmt-label={`Training video ${n} of 4`}
              data-fmt-hint="Double tap to play"
              data-fmt-trait="button">
              <div style={{ position: 'absolute', inset: 0, backgroundImage: 'repeating-linear-gradient(45deg, rgba(255,255,255,0.08) 0 6px, transparent 6px 12px)' }}/>
              <div style={{
                position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <div style={{ width: 40, height: 40, borderRadius: 20, background: 'rgba(0,0,0,0.55)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  <svg width="14" height="16" viewBox="0 0 14 16"><path d="M2 1l11 7-11 7V1z" fill="#fff"/></svg>
                </div>
              </div>
              <div style={{
                position: 'absolute', left: 8, bottom: 8,
                fontFamily: FMT_FONT, fontSize: 13, fontWeight: 600, color: '#fff',
                background: 'rgba(0,0,0,0.5)', padding: '2px 8px', borderRadius: 6,
              }}>{['Front', 'Side', 'Top', 'Other bg'][n - 1]}</div>
            </div>
          ))}
        </div>
      </div>

      <div style={{ padding: 20, display: 'flex', flexDirection: 'column', gap: 12 }}>
        <FMTButton theme={t} scale={scale} variant="primary" label="Find this item"
          icon={FMTIcon.magnifier(22 * scale, t.onAccent)}
          ariaHint={`Starts scanning for ${item.name}`} onClick={onFind}/>
        <FMTButton theme={t} scale={scale} variant="secondary" label="Add more training videos"
          icon={FMTIcon.plus(22 * scale, t.isHC ? t.text : t.accent)}
          ariaHint="Records additional training videos to improve recognition"
          onClick={onRetrain}/>
        <FMTButton theme={t} scale={scale} destructive label="Delete item"
          icon={FMTIcon.trash(22 * scale, t.error)}
          ariaHint="Deletes this item. You will be asked to confirm."
          onClick={onDelete}/>
      </div>
    </div>
  );
}

Object.assign(window, {
  ITEMS_SEED, ScreenOnboarding, ScreenHome, ScreenLibrary, ScreenItemDetail, ItemRow,
});
