// theme.jsx — Find My Things design tokens
// Calm, trustworthy, utilitarian. Close to Apple Magnifier with a small warm accent.

const FMT_THEMES = {
  light: {
    name: 'light',
    bg: '#FFFFFF',
    bgGrouped: '#F2F2F7',
    surface: '#FFFFFF',
    surfaceAlt: '#F2F2F7',
    text: '#000000',
    textSecondary: 'rgba(60,60,67,0.78)',
    textTertiary: 'rgba(60,60,67,0.45)',
    separator: 'rgba(60,60,67,0.18)',
    accent: '#0040DD',
    accentText: '#FFFFFF',
    onAccent: '#FFFFFF',
    success: '#005A2B',
    successBg: '#D9F2E2',
    warning: '#A04500',
    error: '#B00020',
    chipBg: '#EEF1FB',
    chipText: '#0040DD',
    fieldBg: '#F2F2F7',
    overlay: 'rgba(0,0,0,0.55)',
    isDark: false,
  },
  dark: {
    name: 'dark',
    bg: '#000000',
    bgGrouped: '#000000',
    surface: '#1C1C1E',
    surfaceAlt: '#2C2C2E',
    text: '#FFFFFF',
    textSecondary: 'rgba(235,235,245,0.7)',
    textTertiary: 'rgba(235,235,245,0.4)',
    separator: 'rgba(84,84,88,0.65)',
    accent: '#4D8BFF',
    accentText: '#FFFFFF',
    onAccent: '#FFFFFF',
    success: '#4ADE80',
    successBg: '#0F2A1A',
    warning: '#FFA94D',
    error: '#FF6B6B',
    chipBg: '#1C2438',
    chipText: '#4D8BFF',
    fieldBg: '#1C1C1E',
    overlay: 'rgba(0,0,0,0.7)',
    isDark: true,
  },
  hc: {
    name: 'hc',
    bg: '#000000',
    bgGrouped: '#000000',
    surface: '#000000',
    surfaceAlt: '#1A1A1A',
    text: '#FFFFFF',
    textSecondary: '#FFFFFF',
    textTertiary: '#FFFFFF',
    separator: '#FFFFFF',
    accent: '#FFD60A',
    accentText: '#000000',
    onAccent: '#000000',
    success: '#34FF6A',
    successBg: '#0A2A14',
    warning: '#FFB100',
    error: '#FF5555',
    chipBg: '#1A1A1A',
    chipText: '#FFD60A',
    fieldBg: '#1A1A1A',
    overlay: 'rgba(0,0,0,0.85)',
    isDark: true,
    isHC: true,
  },
};

// Dynamic Type scales
const FMT_TYPE_SCALES = {
  default: 1.0,
  ax1: 1.35,
  ax5: 2.1,
};

const FMT_FONT = '-apple-system, "SF Pro", "SF Pro Text", system-ui, sans-serif';
const FMT_FONT_ROUNDED = '-apple-system, "SF Pro Rounded", system-ui, sans-serif';

// Reusable building blocks
function FMTButton({ variant = 'primary', label, sublabel, icon, onClick, theme, scale = 1, ariaHint, dataLabel, height, fullWidth = true, destructive = false }) {
  const t = theme;
  const fs = 22 * scale;
  const sublabelFs = 15 * scale;
  const padV = 18 * Math.max(1, scale * 0.85);
  let bg, fg, border;
  if (destructive) {
    bg = t.isDark ? 'rgba(255,107,107,0.15)' : '#FFEAEA';
    fg = t.error;
    border = 'transparent';
  } else if (variant === 'primary') {
    bg = t.accent; fg = t.onAccent; border = 'transparent';
  } else if (variant === 'secondary') {
    bg = t.isDark ? t.surface : '#EEF1FB';
    fg = t.isHC ? t.text : t.accent;
    border = t.isHC ? `2px solid ${t.text}` : 'transparent';
  } else if (variant === 'ghost') {
    bg = 'transparent'; fg = t.accent; border = 'transparent';
  } else if (variant === 'outline') {
    bg = 'transparent'; fg = t.text; border = `2px solid ${t.text}`;
  }
  return (
    <button
      onClick={onClick}
      data-fmt-label={dataLabel || label}
      data-fmt-hint={ariaHint}
      data-fmt-trait="button"
      style={{
        width: fullWidth ? '100%' : 'auto',
        minHeight: height || 60,
        padding: `${padV}px 20px`,
        borderRadius: 18,
        background: bg, color: fg, border,
        fontFamily: FMT_FONT, fontWeight: 600, fontSize: fs,
        letterSpacing: -0.3,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        gap: 12, cursor: 'pointer',
        boxShadow: variant === 'primary' && !t.isHC ? '0 2px 0 rgba(0,0,0,0.05)' : 'none',
        WebkitTapHighlightColor: 'transparent',
        textAlign: 'center',
        flexDirection: sublabel ? 'column' : 'row',
        lineHeight: 1.15,
      }}
    >
      {sublabel ? (
        <>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            {icon}<span>{label}</span>
          </div>
          <div style={{ fontSize: sublabelFs, fontWeight: 500, opacity: 0.85 }}>{sublabel}</div>
        </>
      ) : (
        <>
          {icon}<span>{label}</span>
        </>
      )}
    </button>
  );
}

function FMTSection({ children, gap = 16 }) {
  return <div style={{ display: 'flex', flexDirection: 'column', gap, padding: '0 20px' }}>{children}</div>;
}

function FMTHeader({ title, theme, scale = 1, leading, trailing, subtitle }) {
  const t = theme;
  return (
    <div style={{ padding: '8px 20px 12px' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', minHeight: 44, marginBottom: 8 }}>
        <div style={{ minWidth: 60, display: 'flex', justifyContent: 'flex-start' }}>{leading}</div>
        <div style={{ minWidth: 60, display: 'flex', justifyContent: 'flex-end' }}>{trailing}</div>
      </div>
      <h1 style={{
        fontFamily: FMT_FONT, fontSize: 34 * scale, fontWeight: 700,
        color: t.text, letterSpacing: -0.6, lineHeight: 1.1, margin: 0,
      }}>{title}</h1>
      {subtitle && (
        <div style={{
          marginTop: 6, fontFamily: FMT_FONT, fontSize: 17 * scale,
          color: t.textSecondary, lineHeight: 1.3,
        }}>{subtitle}</div>
      )}
    </div>
  );
}

// Round icon button (60x60), used for back/close/help
function FMTIconButton({ children, onClick, theme, label, hint, size = 60, variant = 'glass' }) {
  const t = theme;
  let bg, border;
  if (variant === 'glass') {
    bg = t.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.05)';
    border = t.isHC ? `2px solid ${t.text}` : 'none';
  } else if (variant === 'filled') {
    bg = t.accent; border = 'none';
  }
  return (
    <button
      onClick={onClick}
      data-fmt-label={label} data-fmt-hint={hint} data-fmt-trait="button"
      style={{
        width: size, height: size, borderRadius: size / 2,
        background: bg, border, cursor: 'pointer',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: variant === 'filled' ? t.onAccent : t.text,
        WebkitTapHighlightColor: 'transparent',
      }}
    >{children}</button>
  );
}

// SF-symbol-like glyphs (reuse a small set to keep visual consistency)
const FMTIcon = {
  magnifier: (size = 28, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 28 28" fill="none">
      <circle cx="12" cy="12" r="8" stroke={c} strokeWidth="2.6"/>
      <path d="M18 18l6 6" stroke={c} strokeWidth="2.6" strokeLinecap="round"/>
    </svg>
  ),
  plus: (size = 28, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 28 28" fill="none">
      <path d="M14 5v18M5 14h18" stroke={c} strokeWidth="2.8" strokeLinecap="round"/>
    </svg>
  ),
  chevR: (size = 14, c = 'currentColor') => (
    <svg width={size} height={size * 1.5} viewBox="0 0 14 21" fill="none">
      <path d="M2 2l9 8.5-9 8.5" stroke={c} strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  chevL: (size = 14, c = 'currentColor') => (
    <svg width={size} height={size * 1.5} viewBox="0 0 14 21" fill="none">
      <path d="M12 2l-9 8.5 9 8.5" stroke={c} strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  gear: (size = 26, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 26 26" fill="none">
      <circle cx="13" cy="13" r="3.5" stroke={c} strokeWidth="2"/>
      <path d="M13 1.5v3.5M13 21v3.5M1.5 13H5M21 13h3.5M4.8 4.8l2.5 2.5M18.7 18.7l2.5 2.5M21.2 4.8l-2.5 2.5M7.3 18.7l-2.5 2.5" stroke={c} strokeWidth="2" strokeLinecap="round"/>
    </svg>
  ),
  questionCircle: (size = 28, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 28 28" fill="none">
      <circle cx="14" cy="14" r="12" stroke={c} strokeWidth="2.4"/>
      <path d="M10 10.5c0-2.2 1.8-4 4-4s4 1.6 4 3.7c0 2.5-3 2.8-3.5 5.3M14 20.2v.4" stroke={c} strokeWidth="2.4" strokeLinecap="round"/>
    </svg>
  ),
  close: (size = 22, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none">
      <path d="M5 5l12 12M17 5L5 17" stroke={c} strokeWidth="2.6" strokeLinecap="round"/>
    </svg>
  ),
  check: (size = 22, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none">
      <path d="M4 11l5 5 9-11" stroke={c} strokeWidth="2.8" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  mic: (size = 28, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 28 28" fill="none">
      <rect x="10" y="3" width="8" height="14" rx="4" stroke={c} strokeWidth="2.4"/>
      <path d="M5 13a9 9 0 0018 0M14 22v4M9 26h10" stroke={c} strokeWidth="2.4" strokeLinecap="round"/>
    </svg>
  ),
  record: (size = 36, c = '#FF3B30') => (
    <svg width={size} height={size} viewBox="0 0 36 36"><circle cx="18" cy="18" r="14" fill={c}/></svg>
  ),
  bolt: (size = 22, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none">
      <path d="M13 2L4 13h6l-2 7 9-11h-6l2-7z" fill={c}/>
    </svg>
  ),
  speaker: (size = 22, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none">
      <path d="M3 8v6h3l5 4V4L6 8H3z" fill={c}/>
      <path d="M14 8c1.2 1 1.2 5 0 6M16.5 5c2.5 2.5 2.5 9.5 0 12" stroke={c} strokeWidth="1.8" strokeLinecap="round" fill="none"/>
    </svg>
  ),
  trash: (size = 22, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none">
      <path d="M4 6h14M9 3h4M6 6l1 13h8l1-13M9 10v6M13 10v6" stroke={c} strokeWidth="2" strokeLinecap="round"/>
    </svg>
  ),
  star: (size = 22, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none">
      <path d="M11 2l2.7 5.6 6.3.9-4.5 4.4 1.1 6.1L11 16.1 5.4 19l1.1-6.1L2 8.5l6.3-.9L11 2z" stroke={c} strokeWidth="1.8" strokeLinejoin="round"/>
    </svg>
  ),
  clock: (size = 22, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none">
      <circle cx="11" cy="11" r="9" stroke={c} strokeWidth="2"/>
      <path d="M11 6v5l3 2" stroke={c} strokeWidth="2" strokeLinecap="round"/>
    </svg>
  ),
  waveform: (size = 28, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 28 28" fill="none">
      <path d="M2 14h2M6 9v10M10 5v18M14 11v6M18 7v14M22 10v8M26 14h-2" stroke={c} strokeWidth="2.4" strokeLinecap="round"/>
    </svg>
  ),
  hand: (size = 28, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 28 28" fill="none">
      <path d="M9 14V5a2 2 0 014 0v7M13 12V4a2 2 0 014 0v8M17 12V7a2 2 0 014 0v10c0 5-3 8-8 8s-8-3-8-7v-3a2 2 0 014 0v2" stroke={c} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  arrowR: (size = 22, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none">
      <path d="M3 11h16M13 5l6 6-6 6" stroke={c} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  ),
  flashlight: (size = 22, c = 'currentColor') => (
    <svg width={size} height={size} viewBox="0 0 22 22" fill="none">
      <path d="M6 2h10l-1 5H7L6 2zM7 7v9a4 4 0 008 0V7" stroke={c} strokeWidth="2" strokeLinejoin="round"/>
    </svg>
  ),
};

// Object placeholder swatches (for items in library — non-stock visuals)
const FMT_ITEM_SWATCHES = {
  keys: ['#F4C95D', '#9C7B2E'],
  mug: ['#C73E3A', '#7A1F1C'],
  cane: ['#E8E8EE', '#8C8C92'],
  headphones: ['#3B3B40', '#1C1C1E'],
  wallet: ['#5C3A21', '#2E1B0F'],
  remote: ['#2C2C2E', '#1C1C1E'],
  charger: ['#FFFFFF', '#C7C7CC'],
  meds: ['#E29A38', '#A56118'],
};

function FMTItemThumb({ kind = 'keys', size = 56, theme }) {
  const [a, b] = FMT_ITEM_SWATCHES[kind] || FMT_ITEM_SWATCHES.keys;
  return (
    <div style={{
      width: size, height: size, borderRadius: 14,
      background: `linear-gradient(135deg, ${a}, ${b})`,
      flexShrink: 0,
      boxShadow: theme?.isHC ? `0 0 0 2px ${theme.text}` : 'inset 0 0 0 1px rgba(0,0,0,0.05)',
      position: 'relative', overflow: 'hidden',
    }}>
      <div style={{
        position: 'absolute', inset: 0,
        backgroundImage: 'repeating-linear-gradient(45deg, rgba(255,255,255,0.08) 0 6px, transparent 6px 12px)',
      }}/>
    </div>
  );
}

Object.assign(window, {
  FMT_THEMES, FMT_TYPE_SCALES, FMT_FONT, FMT_FONT_ROUNDED,
  FMTButton, FMTSection, FMTHeader, FMTIconButton, FMTIcon,
  FMT_ITEM_SWATCHES, FMTItemThumb,
});
