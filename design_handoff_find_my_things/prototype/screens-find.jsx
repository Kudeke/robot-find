// screens-find.jsx — Item Picker, Scanning (3 variants), Found

// Item Picker ──────────────────────────────────────────────────────────────
function ScreenItemPicker({ theme, scale, items, onPick, onCancel }) {
  const t = theme;
  const recent = items.slice(0, 3);
  const rest = items.slice(3);
  return (
    <div style={{ height: '100%', background: t.bg, color: t.text, display: 'flex', flexDirection: 'column' }}>
      <div style={{ padding: '60px 20px 12px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <FMTIconButton theme={t} size={48} label="Cancel" hint="Cancels finding" onClick={onCancel}>
          {FMTIcon.close(20, t.text)}
        </FMTIconButton>
        <div style={{ fontFamily: FMT_FONT, fontSize: 17 * scale, fontWeight: 600, color: t.text }} data-fmt-trait="header">Find an item</div>
        <div style={{ width: 48 }}/>
      </div>
      <div style={{ padding: '8px 20px' }}>
        <div style={{
          background: t.fieldBg, borderRadius: 14, padding: '14px 16px',
          fontFamily: FMT_FONT, fontSize: 17 * scale, color: t.textSecondary,
          display: 'flex', alignItems: 'center', gap: 10,
          border: t.isHC ? `2px solid ${t.text}` : 'none',
        }} data-fmt-label="Search items" data-fmt-trait="searchField" data-fmt-hint="Type or dictate to search">
          {FMTIcon.magnifier(20 * scale, t.textSecondary)}
          <span>Search items</span>
          <div style={{ flex: 1 }}/>
          {FMTIcon.mic(22 * scale, t.accent)}
        </div>
      </div>
      <div style={{ flex: 1, overflowY: 'auto', padding: '8px 0 24px' }}>
        <div style={{ padding: '12px 28px 8px', fontFamily: FMT_FONT, fontSize: 13 * scale, fontWeight: 600, color: t.textSecondary, textTransform: 'uppercase', letterSpacing: 0.5 }}>
          Recently used
        </div>
        <PickerList items={recent} onPick={onPick} theme={t} scale={scale}/>
        <div style={{ padding: '20px 28px 8px', fontFamily: FMT_FONT, fontSize: 13 * scale, fontWeight: 600, color: t.textSecondary, textTransform: 'uppercase', letterSpacing: 0.5 }}>
          All items
        </div>
        <PickerList items={rest} onPick={onPick} theme={t} scale={scale}/>
      </div>
    </div>
  );
}

function PickerList({ items, onPick, theme, scale }) {
  const t = theme;
  return (
    <div style={{ margin: '0 16px', borderRadius: 18, background: t.surface, overflow: 'hidden', border: t.isHC ? `2px solid ${t.text}` : 'none' }}>
      {items.map((it, i) => (
        <button key={it.id} onClick={() => onPick(it)} style={{
          width: '100%', minHeight: 80, padding: '14px 16px',
          background: 'transparent', border: 'none', cursor: 'pointer',
          display: 'flex', alignItems: 'center', gap: 14, textAlign: 'left',
          borderBottom: i < items.length - 1 ? `0.5px solid ${t.separator}` : 'none',
        }} data-fmt-label={`${it.name}, last used ${it.lastUsed}`} data-fmt-hint="Starts scanning for this item" data-fmt-trait="button">
          <FMTItemThumb kind={it.kind} size={48} theme={t}/>
          <div style={{ flex: 1 }}>
            <div style={{ fontFamily: FMT_FONT, fontSize: 20 * scale, fontWeight: 700, color: t.text, letterSpacing: -0.3 }}>{it.name}</div>
            <div style={{ marginTop: 2, fontFamily: FMT_FONT, fontSize: 14 * scale, color: t.textSecondary }}>{it.lastUsed}</div>
          </div>
          {FMTIcon.chevR(14, t.textTertiary)}
        </button>
      ))}
    </div>
  );
}

// Scanning ─────────────────────────────────────────────────────────────────
// Simulated proximity model: oscillates 0..1; user can also drag the proximity bar.
function useScanSimulation() {
  const [proximity, setProximity] = React.useState(0.15);
  const [dir, setDir] = React.useState(0); // -1..1, left/right
  const [auto, setAuto] = React.useState(true);
  const [phase, setPhase] = React.useState('searching'); // searching | warm | found | lost
  const tRef = React.useRef(0);
  React.useEffect(() => {
    if (!auto) return;
    let raf;
    const tick = () => {
      tRef.current += 0.012;
      const p = 0.55 + 0.42 * Math.sin(tRef.current * 0.8);
      const d = Math.sin(tRef.current * 0.4) * 0.7;
      setProximity(Math.max(0, Math.min(1, p)));
      setDir(d);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [auto]);
  React.useEffect(() => {
    if (proximity > 0.92) setPhase('found');
    else if (proximity > 0.6) setPhase('warm');
    else setPhase('searching');
  }, [proximity]);
  return { proximity, dir, phase, setAuto, auto, setProximity, setDir };
}

// Web Audio sonar
function useSonar(enabled, proximity) {
  const ctxRef = React.useRef(null);
  const lastRef = React.useRef(0);
  React.useEffect(() => {
    if (!enabled) return;
    if (!ctxRef.current) {
      try {
        ctxRef.current = new (window.AudioContext || window.webkitAudioContext)();
      } catch {}
    }
    const ctx = ctxRef.current;
    if (!ctx) return;
    if (ctx.state === 'suspended') ctx.resume();

    let stop = false;
    const tick = () => {
      if (stop || !enabled) return;
      const rate = 0.5 + proximity * 7.5; // Hz
      const interval = 1000 / rate;
      const now = performance.now();
      if (now - lastRef.current > interval) {
        lastRef.current = now;
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'sine';
        osc.frequency.value = 440 + proximity * 800;
        gain.gain.value = 0;
        gain.gain.setValueAtTime(0, ctx.currentTime);
        gain.gain.linearRampToValueAtTime(0.18, ctx.currentTime + 0.01);
        gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.12);
        osc.connect(gain).connect(ctx.destination);
        osc.start();
        osc.stop(ctx.currentTime + 0.14);
      }
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
    return () => { stop = true; };
  }, [enabled, proximity]);
}

function ScanningHeader({ theme, scale, item, onClose, dark = true }) {
  return (
    <div style={{ position: 'absolute', top: 0, left: 0, right: 0, zIndex: 5,
      paddingTop: 60, paddingBottom: 14, paddingLeft: 16, paddingRight: 16,
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      background: 'linear-gradient(to bottom, rgba(0,0,0,0.7), rgba(0,0,0,0))',
    }}>
      <div style={{ flex: 1, color: '#fff', fontFamily: FMT_FONT }}>
        <div style={{ fontSize: 13 * scale, fontWeight: 600, opacity: 0.7, textTransform: 'uppercase', letterSpacing: 0.5 }}>Looking for</div>
        <div style={{ fontSize: 22 * scale, fontWeight: 700, letterSpacing: -0.4, marginTop: 2 }} data-fmt-trait="header">{item.name}</div>
      </div>
      <button onClick={onClose} data-fmt-label="Stop scanning" data-fmt-hint="Exits scanning" data-fmt-trait="button" style={{
        width: 60, height: 60, borderRadius: 30,
        background: 'rgba(0,0,0,0.6)', border: '2px solid rgba(255,255,255,0.4)',
        color: '#fff', cursor: 'pointer',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        {FMTIcon.close(24, '#fff')}
      </button>
    </div>
  );
}

// Variant 1: Sonar bar — minimal, audio-first ─────────────────────────────
function ScanningVariantBar({ theme, scale, item, onFound, onCancel, audio }) {
  const { proximity, dir, phase, setAuto, setProximity } = useScanSimulation();
  useSonar(audio && phase !== 'found', proximity);
  const t = theme;

  const directionLabel = Math.abs(dir) < 0.15 ? 'Hold steady' : dir > 0 ? 'Pan right' : 'Pan left';
  const distFt = Math.max(0.5, (1 - proximity) * 8).toFixed(1);

  return (
    <div style={{ height: '100%', background: '#000', position: 'relative', overflow: 'hidden' }}>
      {/* mock camera feed */}
      <div style={{ position: 'absolute', inset: 0,
        background: `radial-gradient(circle at ${50 + dir * 30}% ${40 - proximity * 10}%, #3a3a40, #08080a 70%)`,
        transition: 'background 200ms' }}/>
      {/* moving target */}
      <div style={{
        position: 'absolute', left: '50%', top: '40%',
        transform: `translate(${-50 + dir * 30}%, -50%) scale(${0.6 + proximity * 0.6})`,
        width: 110, height: 110, borderRadius: 26,
        background: `linear-gradient(135deg, ${FMT_ITEM_SWATCHES[item.kind][0]}, ${FMT_ITEM_SWATCHES[item.kind][1]})`,
        opacity: 0.3 + proximity * 0.7,
        boxShadow: phase === 'found' ? '0 0 80px 20px rgba(255,214,10,0.5)' : '0 20px 60px rgba(0,0,0,0.5)',
        transition: 'box-shadow 200ms',
      }}/>
      {/* bounding box when found */}
      {phase !== 'searching' && (
        <div style={{
          position: 'absolute', left: '50%', top: '40%',
          transform: `translate(${-50 + dir * 30}%, -50%) scale(${0.6 + proximity * 0.6})`,
          width: 150, height: 150, marginLeft: -20, marginTop: -20,
          border: `4px solid ${phase === 'found' ? '#FFD60A' : 'rgba(255,214,10,0.6)'}`,
          borderRadius: 16,
        }}/>
      )}

      <ScanningHeader theme={t} scale={scale} item={item} onClose={onCancel}/>

      {/* central reticle */}
      <div style={{ position: 'absolute', left: '50%', top: '50%', transform: 'translate(-50%, -50%)', pointerEvents: 'none' }}>
        <svg width="80" height="80" viewBox="0 0 80 80" fill="none">
          <circle cx="40" cy="40" r="34" stroke="rgba(255,255,255,0.4)" strokeWidth="2" strokeDasharray="4 6"/>
          <path d="M40 14v12M40 54v12M14 40h12M54 40h12" stroke="rgba(255,255,255,0.6)" strokeWidth="2" strokeLinecap="round"/>
        </svg>
      </div>

      {/* bottom HUD */}
      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0,
        padding: '24px 20px 36px',
        background: 'linear-gradient(to top, rgba(0,0,0,0.85), rgba(0,0,0,0))',
      }}>
        {/* spoken nudge caption */}
        <div style={{
          minHeight: 56, padding: '14px 18px', borderRadius: 14,
          background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(20px)',
          fontFamily: FMT_FONT, color: '#fff', fontSize: 18 * scale, fontWeight: 600,
          textAlign: 'center', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
        }} data-fmt-label={phase === 'found' ? `Found ${item.name}, about ${distFt} feet ahead` : `${directionLabel}, ${distFt} feet`}
           data-fmt-trait="updatesFrequently">
          {phase === 'found' ? <span>✓ Found! About {distFt} ft ahead</span> : <span>{directionLabel} • {distFt} ft</span>}
        </div>

        {/* proximity bar */}
        <div style={{ marginTop: 20 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8,
            fontFamily: FMT_FONT, fontSize: 13 * scale, color: 'rgba(255,255,255,0.7)', fontWeight: 600, letterSpacing: 0.5, textTransform: 'uppercase' }}>
            <span>Cold</span><span>Getting warmer</span><span>Hot</span>
          </div>
          <div style={{ position: 'relative', height: 14, borderRadius: 7, background: 'rgba(255,255,255,0.15)', overflow: 'hidden' }}
            data-fmt-label={`Proximity: ${Math.round(proximity * 100)} percent`} data-fmt-trait="updatesFrequently progressBar">
            <div style={{
              position: 'absolute', inset: 0, width: `${proximity * 100}%`,
              background: `linear-gradient(90deg, #4D8BFF, #FFD60A ${50}%, #FF453A 90%)`,
              transition: 'width 100ms',
            }}/>
          </div>
        </div>

        {/* direction indicator */}
        <div style={{ marginTop: 14, position: 'relative', height: 36, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ position: 'absolute', left: '50%', top: '50%', width: 4, height: 36, marginTop: -18, background: 'rgba(255,255,255,0.4)' }}/>
          <div style={{
            position: 'absolute', left: `${50 + dir * 40}%`, top: 0, transform: 'translateX(-50%)',
            transition: 'left 100ms',
          }}>
            <svg width="36" height="36" viewBox="0 0 36 36" fill="none">
              <path d="M18 4L32 28H4z" fill="#FFD60A" stroke="#000" strokeWidth="1.5"/>
            </svg>
          </div>
        </div>

        {phase === 'found' && (
          <button onClick={onFound} style={{
            marginTop: 16, width: '100%', minHeight: 64, borderRadius: 18,
            background: '#FFD60A', color: '#000', border: 'none', cursor: 'pointer',
            fontFamily: FMT_FONT, fontSize: 22 * scale, fontWeight: 700, letterSpacing: -0.3,
          }} data-fmt-label="Confirm found" data-fmt-hint="Confirms the item is found">
            Confirm found
          </button>
        )}
      </div>

      {/* scrub control to drive the simulation manually */}
      <div style={{ position: 'absolute', bottom: 200, right: 16, padding: '8px 10px', borderRadius: 999, background: 'rgba(0,0,0,0.55)', display: 'flex', gap: 8, alignItems: 'center', fontFamily: FMT_FONT, fontSize: 12, color: '#fff' }}>
        <span style={{ opacity: 0.7 }}>SIM</span>
        <input type="range" min="0" max="1" step="0.01" value={proximity}
          onChange={e => { setAuto(false); setProximity(parseFloat(e.target.value)); }}
          style={{ width: 90 }}/>
      </div>
    </div>
  );
}

// Variant 2: Radar visualizer — circular pulse ─────────────────────────────
function ScanningVariantRadar({ theme, scale, item, onFound, onCancel, audio }) {
  const { proximity, dir, phase, setAuto, setProximity } = useScanSimulation();
  useSonar(audio && phase !== 'found', proximity);
  const t = theme;

  const distFt = Math.max(0.5, (1 - proximity) * 8).toFixed(1);
  const directionLabel = Math.abs(dir) < 0.15 ? 'Hold steady' : dir > 0 ? 'Pan right' : 'Pan left';
  const angle = dir * 60; // degrees from straight ahead

  return (
    <div style={{ height: '100%', background: '#000', position: 'relative', overflow: 'hidden' }}>
      {/* radar/camera blend */}
      <div style={{ position: 'absolute', inset: 0,
        background: `radial-gradient(circle at 50% 55%, ${proximity > 0.6 ? '#1f1a08' : '#0a0c1a'} 0%, #000 75%)`,
        transition: 'background 300ms' }}/>

      <ScanningHeader theme={t} scale={scale} item={item} onClose={onCancel}/>

      {/* radar ring stack */}
      <div style={{ position: 'absolute', left: '50%', top: '52%', transform: 'translate(-50%, -50%)' }}>
        <svg width="320" height="320" viewBox="0 0 320 320">
          <defs>
            <radialGradient id="fmtRadarG" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor={phase === 'found' ? '#FFD60A' : '#4D8BFF'} stopOpacity="0.5"/>
              <stop offset="100%" stopColor="transparent"/>
            </radialGradient>
          </defs>
          <circle cx="160" cy="160" r="150" stroke="rgba(255,255,255,0.08)" strokeWidth="1.5" fill="none"/>
          <circle cx="160" cy="160" r="110" stroke="rgba(255,255,255,0.10)" strokeWidth="1.5" fill="none"/>
          <circle cx="160" cy="160" r="70" stroke="rgba(255,255,255,0.12)" strokeWidth="1.5" fill="none"/>
          <circle cx="160" cy="160" r="30" stroke="rgba(255,255,255,0.16)" strokeWidth="1.5" fill="none"/>
          {/* expanding pulse keyed to proximity */}
          {[0, 1, 2].map(i => {
            const phase = (Date.now() / 1000 + i * 0.4) % 1.5;
            const r = 30 + phase * 110;
            const op = 0.6 - phase / 1.5 * 0.6;
            return <circle key={i} cx="160" cy="160" r={r} stroke="#4D8BFF" strokeWidth="2" fill="none" opacity={op}/>;
          })}
          {/* sweep arm */}
          <g transform={`rotate(${angle - 90} 160 160)`}>
            <path d="M160 160 L310 160 A150 150 0 0 0 270 70 Z" fill="url(#fmtRadarG)" opacity={0.7}/>
            <line x1="160" y1="160" x2="310" y2="160" stroke="#4D8BFF" strokeWidth="2.5"/>
          </g>
          {/* target blip */}
          <g transform={`translate(${160 + Math.cos((angle - 90) * Math.PI / 180) * (30 + (1 - proximity) * 110)}, ${160 + Math.sin((angle - 90) * Math.PI / 180) * (30 + (1 - proximity) * 110)})`}>
            <circle r={proximity > 0.92 ? 22 : 14} fill={phase === 'found' ? '#FFD60A' : '#FF6B6B'} opacity={0.6}/>
            <circle r={8} fill={phase === 'found' ? '#FFD60A' : '#FF6B6B'}/>
          </g>
          {/* center */}
          <circle cx="160" cy="160" r="6" fill="#fff"/>
        </svg>
      </div>

      {/* HUD */}
      <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, padding: '24px 20px 36px',
        background: 'linear-gradient(to top, rgba(0,0,0,0.9), rgba(0,0,0,0))' }}>
        <div style={{ display: 'flex', gap: 12, marginBottom: 16 }}>
          <HudTile label="Distance" value={`${distFt} ft`} theme={t} scale={scale}/>
          <HudTile label="Confidence" value={`${Math.round(proximity * 100)}%`} theme={t} scale={scale}/>
          <HudTile label="Direction" value={directionLabel} theme={t} scale={scale}/>
        </div>
        <div style={{
          minHeight: 64, padding: '16px 18px', borderRadius: 16,
          background: phase === 'found' ? '#FFD60A' : 'rgba(0,0,0,0.6)',
          color: phase === 'found' ? '#000' : '#fff',
          backdropFilter: 'blur(20px)',
          fontFamily: FMT_FONT, fontSize: 19 * scale, fontWeight: 700,
          textAlign: 'center', letterSpacing: -0.3,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
        }} data-fmt-label={phase === 'found' ? `Found ${item.name}` : `${directionLabel}, ${distFt} feet`} data-fmt-trait="updatesFrequently">
          {phase === 'found' ? `✓ Found! Tap to confirm` : (proximity > 0.6 ? 'Getting warmer…' : 'Pan slowly')}
        </div>
        {phase === 'found' && (
          <button onClick={onFound} style={{
            marginTop: 12, width: '100%', minHeight: 60, borderRadius: 18,
            background: '#fff', color: '#000', border: 'none', cursor: 'pointer',
            fontFamily: FMT_FONT, fontSize: 20 * scale, fontWeight: 700,
          }} data-fmt-label="Confirm found">Confirm found</button>
        )}
      </div>

      <div style={{ position: 'absolute', bottom: 240, right: 16, padding: '8px 10px', borderRadius: 999, background: 'rgba(0,0,0,0.55)', display: 'flex', gap: 8, alignItems: 'center', fontFamily: FMT_FONT, fontSize: 12, color: '#fff' }}>
        <span style={{ opacity: 0.7 }}>SIM</span>
        <input type="range" min="0" max="1" step="0.01" value={proximity}
          onChange={e => { setAuto(false); setProximity(parseFloat(e.target.value)); }}
          style={{ width: 90 }}/>
      </div>
    </div>
  );
}

function HudTile({ label, value, theme, scale }) {
  return (
    <div style={{ flex: 1, padding: '10px 12px', borderRadius: 12, background: 'rgba(255,255,255,0.08)', border: '1px solid rgba(255,255,255,0.12)' }}>
      <div style={{ fontFamily: FMT_FONT, fontSize: 11 * scale, fontWeight: 700, color: 'rgba(255,255,255,0.6)', textTransform: 'uppercase', letterSpacing: 0.5 }}>{label}</div>
      <div style={{ marginTop: 4, fontFamily: FMT_FONT, fontSize: 18 * scale, fontWeight: 700, color: '#fff', letterSpacing: -0.3 }}>{value}</div>
    </div>
  );
}

// Variant 3: Heatmap with bounding box ─────────────────────────────────────
function ScanningVariantHeatmap({ theme, scale, item, onFound, onCancel, audio }) {
  const { proximity, dir, phase, setAuto, setProximity } = useScanSimulation();
  useSonar(audio && phase !== 'found', proximity);
  const t = theme;

  const distFt = Math.max(0.5, (1 - proximity) * 8).toFixed(1);
  const heatColor = proximity > 0.92 ? '#FFD60A' : proximity > 0.6 ? '#FF8A3D' : proximity > 0.3 ? '#4D8BFF' : '#1F3A6E';
  const targetX = 50 + dir * 30;
  const targetY = 38;

  return (
    <div style={{ height: '100%', background: '#000', position: 'relative', overflow: 'hidden' }}>
      {/* heatmap overlay on mock cam */}
      <div style={{ position: 'absolute', inset: 0,
        background: `radial-gradient(circle at ${targetX}% ${targetY}%, ${heatColor}cc 0%, ${heatColor}55 25%, transparent 55%), linear-gradient(180deg, #1a1a1f, #08080a)` }}/>
      {/* grid */}
      <div style={{ position: 'absolute', inset: 0,
        backgroundImage: 'linear-gradient(to right, rgba(255,255,255,0.04) 1px, transparent 1px), linear-gradient(to bottom, rgba(255,255,255,0.04) 1px, transparent 1px)',
        backgroundSize: '40px 40px', opacity: 0.6 }}/>

      {/* mock object */}
      <div style={{
        position: 'absolute', left: `${targetX}%`, top: `${targetY}%`,
        transform: `translate(-50%, -50%) scale(${0.5 + proximity * 0.7})`,
        width: 110, height: 110, borderRadius: 24,
        background: `linear-gradient(135deg, ${FMT_ITEM_SWATCHES[item.kind][0]}, ${FMT_ITEM_SWATCHES[item.kind][1]})`,
        opacity: 0.4 + proximity * 0.6,
      }}/>

      {/* bounding box (always visible, intensity tied to proximity) */}
      <div style={{
        position: 'absolute', left: `${targetX}%`, top: `${targetY}%`,
        transform: `translate(-50%, -50%) scale(${0.6 + proximity * 0.7})`,
        width: 170, height: 170,
        border: `4px solid ${phase === 'found' ? '#FFD60A' : '#fff'}`,
        borderRadius: 16,
        boxShadow: phase === 'found' ? '0 0 40px rgba(255,214,10,0.7)' : 'none',
      }}>
        <div style={{
          position: 'absolute', top: -38, left: 0, padding: '4px 10px', borderRadius: 6,
          background: phase === 'found' ? '#FFD60A' : 'rgba(0,0,0,0.7)',
          color: phase === 'found' ? '#000' : '#fff',
          fontFamily: FMT_FONT, fontSize: 13, fontWeight: 700, letterSpacing: 0.3,
        }}>
          {item.name.toUpperCase()} • {Math.round(proximity * 100)}%
        </div>
      </div>

      <ScanningHeader theme={t} scale={scale} item={item} onClose={onCancel}/>

      {/* directional chevrons on edges */}
      {Math.abs(dir) > 0.2 && (
        <div style={{
          position: 'absolute', top: '50%', transform: 'translateY(-50%)',
          [dir > 0 ? 'right' : 'left']: 20,
          color: '#FFD60A',
          animation: 'fmtArrow 1s infinite',
        }}>
          {dir > 0 ? FMTIcon.chevR(48, '#FFD60A') : FMTIcon.chevL(48, '#FFD60A')}
        </div>
      )}

      {/* HUD */}
      <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, padding: '24px 20px 36px',
        background: 'linear-gradient(to top, rgba(0,0,0,0.85), rgba(0,0,0,0))' }}>
        <div style={{
          padding: '16px 18px', borderRadius: 16, background: 'rgba(0,0,0,0.65)', backdropFilter: 'blur(20px)',
          fontFamily: FMT_FONT, color: '#fff',
        }} data-fmt-label={`${item.name}, ${Math.round(proximity * 100)} percent confidence, about ${distFt} feet ${dir > 0.15 ? 'to your right' : dir < -0.15 ? 'to your left' : 'ahead'}`} data-fmt-trait="updatesFrequently">
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 6 }}>
            <span style={{ fontSize: 38 * scale, fontWeight: 700, letterSpacing: -1, lineHeight: 1 }}>{distFt}</span>
            <span style={{ fontSize: 18 * scale, fontWeight: 600, opacity: 0.7 }}>ft ahead</span>
          </div>
          <div style={{ fontSize: 16 * scale, fontWeight: 500, opacity: 0.9 }}>
            {phase === 'found' ? `Locked on ${item.name}` : (Math.abs(dir) < 0.15 ? 'Hold steady — getting closer' : dir > 0 ? 'Pan to your right' : 'Pan to your left')}
          </div>
        </div>

        <div style={{ marginTop: 12, display: 'flex', gap: 8 }}>
          {[0.2, 0.4, 0.6, 0.8, 1.0].map((threshold, i) => (
            <div key={i} style={{
              flex: 1, height: 10, borderRadius: 5,
              background: proximity >= threshold - 0.2 ? ['#1F3A6E','#4D8BFF','#FF8A3D','#FFA94D','#FFD60A'][i] : 'rgba(255,255,255,0.12)',
              transition: 'background 200ms',
            }}/>
          ))}
        </div>

        {phase === 'found' && (
          <button onClick={onFound} style={{
            marginTop: 16, width: '100%', minHeight: 64, borderRadius: 18,
            background: '#FFD60A', color: '#000', border: 'none', cursor: 'pointer',
            fontFamily: FMT_FONT, fontSize: 22 * scale, fontWeight: 700,
          }} data-fmt-label="Confirm found">Confirm found</button>
        )}
      </div>

      <div style={{ position: 'absolute', bottom: 230, right: 16, padding: '8px 10px', borderRadius: 999, background: 'rgba(0,0,0,0.55)', display: 'flex', gap: 8, alignItems: 'center', fontFamily: FMT_FONT, fontSize: 12, color: '#fff' }}>
        <span style={{ opacity: 0.7 }}>SIM</span>
        <input type="range" min="0" max="1" step="0.01" value={proximity}
          onChange={e => { setAuto(false); setProximity(parseFloat(e.target.value)); }}
          style={{ width: 90 }}/>
      </div>
      <style>{`@keyframes fmtArrow { 0%,100%{transform:translateY(-50%) translateX(0)} 50%{transform:translateY(-50%) translateX(${dir > 0 ? 8 : -8}px)} }`}</style>
    </div>
  );
}

function ScreenScanning({ variant = 'bar', ...rest }) {
  if (variant === 'radar') return <ScanningVariantRadar {...rest}/>;
  if (variant === 'heatmap') return <ScanningVariantHeatmap {...rest}/>;
  return <ScanningVariantBar {...rest}/>;
}

// Found ────────────────────────────────────────────────────────────────────
function ScreenFound({ theme, scale, item, onFindAgain, onAnother, onDone }) {
  const t = theme;
  return (
    <div style={{ height: '100%', background: t.bg, color: t.text, display: 'flex', flexDirection: 'column' }}>
      <div style={{ paddingTop: 60, padding: '60px 20px 12px', display: 'flex', justifyContent: 'flex-end' }}>
        <FMTIconButton theme={t} size={48} label="Done" hint="Closes the found screen" onClick={onDone}>
          {FMTIcon.close(20, t.text)}
        </FMTIconButton>
      </div>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '0 28px', textAlign: 'center', gap: 28 }}>
        <div style={{
          width: 156, height: 156, borderRadius: 78,
          background: t.successBg, color: t.success,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          border: t.isHC ? `3px solid ${t.success}` : 'none',
        }} data-fmt-label="Success" data-fmt-trait="image">
          {FMTIcon.check(80, t.success)}
        </div>
        <div>
          <h1 style={{ fontFamily: FMT_FONT, fontSize: 36 * scale, fontWeight: 700, color: t.success, letterSpacing: -0.6, margin: 0, lineHeight: 1.1 }} data-fmt-trait="header">
            Found!
          </h1>
          <p style={{ marginTop: 12, fontFamily: FMT_FONT, fontSize: 22 * scale, color: t.text, fontWeight: 600, lineHeight: 1.3, textWrap: 'pretty' }}>
            {item.name}
          </p>
          <p style={{ marginTop: 6, fontFamily: FMT_FONT, fontSize: 17 * scale, color: t.textSecondary, lineHeight: 1.4 }}>
            About 1 foot ahead, slightly to your right.
          </p>
        </div>
      </div>
      <div style={{ padding: '20px 20px 36px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        <FMTButton theme={t} scale={scale} variant="primary" label="Find again"
          ariaHint="Continues scanning for the same item"
          icon={FMTIcon.magnifier(22 * scale, t.onAccent)}
          onClick={onFindAgain} height={68 * Math.max(1, scale * 0.85)}/>
        <FMTButton theme={t} scale={scale} variant="secondary" label="Find another item"
          ariaHint="Returns to the item picker"
          onClick={onAnother}/>
        <FMTButton theme={t} scale={scale} variant="ghost" label="Done"
          ariaHint="Closes scanning and returns Home"
          onClick={onDone}/>
      </div>
    </div>
  );
}

Object.assign(window, {
  ScreenItemPicker, ScreenScanning, ScreenFound,
  ScanningVariantBar, ScanningVariantRadar, ScanningVariantHeatmap,
});
