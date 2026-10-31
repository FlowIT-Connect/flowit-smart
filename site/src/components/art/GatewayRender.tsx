/**
 * Rendu conceptuel de la Solea Gateway (vue de face, de côté, mise en situation).
 * Toujours affiché avec la mention « illustration conceptuelle, rendu non contractuel ».
 */
type View = "front" | "side" | "situ";

function Defs({ id }: { id: string }) {
  return (
    <defs>
      <linearGradient id={`${id}-body`} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#ffffff" />
        <stop offset=".6" stopColor="#f3eee8" />
        <stop offset="1" stopColor="#ddd4c9" />
      </linearGradient>
      <linearGradient id={`${id}-top`} x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stopColor="#ffffff" />
        <stop offset="1" stopColor="#ece5dc" />
      </linearGradient>
      <linearGradient id={`${id}-sun`} x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stopColor="#FFC93C" />
        <stop offset=".55" stopColor="#F28C1B" />
        <stop offset="1" stopColor="#EE6A1F" />
      </linearGradient>
      <radialGradient id={`${id}-glow`} cx=".5" cy=".5" r=".5">
        <stop offset="0" stopColor="#f28c1b" stopOpacity=".55" />
        <stop offset="1" stopColor="#f28c1b" stopOpacity="0" />
      </radialGradient>
      <filter id={`${id}-shadow`} x="-30%" y="-30%" width="160%" height="180%">
        <feGaussianBlur in="SourceAlpha" stdDeviation="10" />
        <feOffset dy="14" />
        <feComponentTransfer><feFuncA type="linear" slope=".25" /></feComponentTransfer>
        <feMerge><feMergeNode /><feMergeNode in="SourceGraphic" /></feMerge>
      </filter>
    </defs>
  );
}

function Sun({ cx, cy, r, id }: { cx: number; cy: number; r: number; id: string }) {
  return (
    <g>
      <circle cx={cx} cy={cy} r={r * 0.44} fill={`url(#${id}-sun)`} />
      {Array.from({ length: 8 }, (_, i) => {
        const a = (i * Math.PI) / 4 - Math.PI / 2;
        return <line key={i} x1={cx + Math.cos(a) * r * 0.64} y1={cy + Math.sin(a) * r * 0.64} x2={cx + Math.cos(a) * r * 0.9} y2={cy + Math.sin(a) * r * 0.9} stroke={`url(#${id}-sun)`} strokeWidth={r * 0.15} strokeLinecap="round" />;
      })}
    </g>
  );
}

export function GatewayRender({ view, className = "", title }: { view: View; className?: string; title?: string }) {
  const id = `gw-${view}`;
  if (view === "front") {
    return (
      <svg viewBox="0 0 400 300" className={className} role="img" aria-label={title}>
        <Defs id={id} />
        <ellipse cx="200" cy="250" rx="130" ry="16" fill="#000" opacity=".12" />
        <g filter={`url(#${id}-shadow)`}>
          <rect x="80" y="70" width="240" height="170" rx="44" fill={`url(#${id}-body)`} />
          <rect x="80.5" y="70.5" width="239" height="169" rx="43.5" fill="none" stroke="#fff" strokeOpacity=".9" />
        </g>
        <circle cx="200" cy="150" r="56" fill={`url(#${id}-glow)`} className="animate-glow" />
        <Sun cx={200} cy={150} r={34} id={id} />
        <text x="200" y="218" textAnchor="middle" fontFamily="var(--font-manrope)" fontWeight="800" fontSize="15" letterSpacing="3" fill="#5c544b">SOLEA</text>
        <rect x="170" y="230" width="60" height="3" rx="1.5" fill={`url(#${id}-sun)`} opacity=".85" />
      </svg>
    );
  }
  if (view === "side") {
    return (
      <svg viewBox="0 0 400 300" className={className} role="img" aria-label={title}>
        <Defs id={id} />
        <ellipse cx="200" cy="250" rx="120" ry="14" fill="#000" opacity=".12" />
        <g filter={`url(#${id}-shadow)`}>
          <path d="M110 90 h180 a30 30 0 0 1 30 30 v95 a25 25 0 0 1 -25 25 h-190 a25 25 0 0 1 -25 -25 v-95 a30 30 0 0 1 30 -30z" fill={`url(#${id}-body)`} />
        </g>
        <path d="M95 112 h210" stroke="#fff" strokeWidth="2" opacity=".9" />
        {[0, 1, 2, 3, 4, 5].map((i) => <rect key={i} x={140 + i * 22} y="200" width="12" height="4" rx="2" fill="#cfc4b6" />)}
        <rect x="270" y="150" width="22" height="12" rx="3" fill="#bdb1a2" />
        <rect x="108" y="150" width="14" height="8" rx="2" fill="#bdb1a2" />
        <rect x="100" y="238" width="200" height="6" rx="3" fill={`url(#${id}-sun)`} opacity=".7" className="animate-glow" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 400 300" className={className} role="img" aria-label={title}>
      <Defs id={id} />
      <rect width="400" height="300" fill="#f4ede3" />
      <rect x="0" y="210" width="400" height="90" fill="#e7dccd" />
      <rect x="0" y="206" width="400" height="6" fill="#d8c9b5" />
      <rect x="250" y="40" width="110" height="150" rx="6" fill="#fffaf2" stroke="#e3d4c0" />
      <rect x="262" y="52" width="86" height="126" rx="3" fill="#ffe2a8" opacity=".6" />
      <rect x="40" y="168" width="180" height="40" rx="8" fill="#cbb79c" />
      <rect x="48" y="176" width="164" height="4" rx="2" fill="#b39e82" />
      <ellipse cx="110" cy="166" rx="30" ry="4" fill="#000" opacity=".12" />
      <rect x="80" y="122" width="60" height="44" rx="12" fill={`url(#${id}-body)`} />
      <Sun cx={110} cy={142} r={13} id={id} />
      <circle cx="110" cy="142" r="40" fill={`url(#${id}-glow)`} opacity=".7" className="animate-glow" />
      <path d="M170 100 q20 -20 40 0 M162 88 q28 -30 56 0" fill="none" stroke="#f28c1b" strokeWidth="3" strokeLinecap="round" opacity=".7" className="animate-glow" />
      <rect x="174" y="150" width="18" height="18" rx="5" fill="#fff" stroke="#e3d4c0" />
      <circle cx="183" cy="159" r="3" fill="#f28c1b" />
      <path d="M300 230 l10 -40 h20 l10 40z" fill="#cbb79c" />
      <circle cx="320" cy="180" r="18" fill="#fff6e3" stroke="#e3d4c0" />
    </svg>
  );
}
