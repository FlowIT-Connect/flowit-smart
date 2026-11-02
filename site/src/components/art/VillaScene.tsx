/**
 * Illustration vectorielle d'une villa contemporaine au crépuscule, fenêtres éclairées.
 * Sert de visuel principal en attendant les photographies sous licence (voir docs).
 */
export function VillaScene({ className = "", title }: { className?: string; title?: string }) {
  return (
    <svg viewBox="0 0 800 560" className={className} role="img" aria-label={title}>
      <defs>
        <linearGradient id="vs-sky" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#120f0c" />
          <stop offset=".55" stopColor="#2a1c12" />
          <stop offset="1" stopColor="#4a2a12" />
        </linearGradient>
        <radialGradient id="vs-sun" cx="0.78" cy="0.62" r="0.5">
          <stop offset="0" stopColor="#ffb547" stopOpacity=".55" />
          <stop offset=".45" stopColor="#ee6a1f" stopOpacity=".18" />
          <stop offset="1" stopColor="#ee6a1f" stopOpacity="0" />
        </radialGradient>
        <linearGradient id="vs-win" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#ffd88a" />
          <stop offset=".6" stopColor="#ffb547" />
          <stop offset="1" stopColor="#f28c1b" />
        </linearGradient>
        <linearGradient id="vs-win-dim" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#ffcf7a" stopOpacity=".75" />
          <stop offset="1" stopColor="#d9730a" stopOpacity=".6" />
        </linearGradient>
        <linearGradient id="vs-wall" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#2b241e" />
          <stop offset="1" stopColor="#1b1612" />
        </linearGradient>
        <linearGradient id="vs-wall-light" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#3a3029" />
          <stop offset="1" stopColor="#2a221c" />
        </linearGradient>
        <linearGradient id="vs-pool" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#1f6f86" />
          <stop offset="1" stopColor="#0d2f3a" />
        </linearGradient>
        <linearGradient id="vs-ground" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#1a1410" />
          <stop offset="1" stopColor="#0e0c0a" />
        </linearGradient>
        <filter id="vs-blur" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="14" /></filter>
        <filter id="vs-soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="3" /></filter>
      </defs>

      <rect width="800" height="560" fill="url(#vs-sky)" />
      <rect width="800" height="560" fill="url(#vs-sun)" />
      {[[60, 50], [140, 90], [230, 40], [330, 75], [420, 30], [520, 64], [610, 36], [700, 80], [760, 26], [95, 140], [280, 120], [480, 118]].map(([x, y], i) => (
        <circle key={i} cx={x} cy={y} r={i % 3 ? 1 : 1.6} fill="#fff" opacity={0.35 + (i % 4) * 0.12} className="animate-glow" style={{ animationDelay: `${i * 0.4}s` }} />
      ))}

      {/* collines */}
      <path d="M0 360 C120 330 220 345 330 330 S560 300 800 320 V560 H0Z" fill="#1d1510" />
      <path d="M0 390 C160 370 300 380 420 372 S650 355 800 368 V560 H0Z" fill="#17110d" />

      {/* halo des fenêtres */}
      <ellipse cx="420" cy="330" rx="260" ry="90" fill="#f28c1b" opacity=".22" filter="url(#vs-blur)" />

      {/* volume bas */}
      <rect x="150" y="300" width="520" height="120" fill="url(#vs-wall)" />
      <rect x="150" y="296" width="520" height="8" fill="#3d332b" />
      {/* baies vitrées du bas */}
      <rect x="182" y="322" width="150" height="88" rx="2" fill="url(#vs-win)" />
      <rect x="342" y="322" width="150" height="88" rx="2" fill="url(#vs-win)" />
      <rect x="502" y="322" width="70" height="88" rx="2" fill="url(#vs-win-dim)" />
      {[257, 417].map((x) => <rect key={x} x={x} y="322" width="2" height="88" fill="#2b241e" opacity=".7" />)}
      {/* silhouettes intérieures */}
      <rect x="215" y="372" width="70" height="20" rx="8" fill="#8a4a12" opacity=".55" />
      <circle cx="390" cy="350" r="9" fill="#fff4d6" opacity=".95" />
      <path d="M383 359 h14 l-3 10 h-8z" fill="#8a4a12" opacity=".5" />
      <rect x="436" y="362" width="4" height="48" fill="#8a4a12" opacity=".35" />

      {/* volume haut en porte-à-faux */}
      <rect x="250" y="200" width="460" height="100" fill="url(#vs-wall-light)" />
      <rect x="240" y="192" width="480" height="10" fill="#4a3e34" />
      <rect x="282" y="222" width="230" height="62" rx="2" fill="url(#vs-win)" />
      <rect x="522" y="222" width="90" height="62" rx="2" fill="url(#vs-win-dim)" />
      <rect x="622" y="222" width="60" height="62" rx="2" fill="#2e2620" />
      <rect x="397" y="222" width="2" height="62" fill="#2b241e" opacity=".6" />
      {/* lames brise-soleil */}
      {Array.from({ length: 6 }, (_, i) => <rect key={i} x={627 + i * 9} y="222" width="3" height="62" fill="#5b4a3c" />)}

      {/* auvent et poteau */}
      <rect x="110" y="292" width="90" height="6" fill="#4a3e34" />
      <rect x="118" y="298" width="4" height="122" fill="#3a3029" />

      {/* éclairage de façade */}
      {[200, 320, 440, 560, 650].map((x, i) => (
        <g key={x}>
          <circle cx={x} cy="306" r="2.4" fill="#ffe2a8" />
          <path d={`M${x - 3} 308 L${x - 18} 360 L${x + 18} 360 L${x + 3} 308Z`} fill="#ffcf7a" opacity=".1" className="animate-glow" style={{ animationDelay: `${i * 0.6}s` }} />
        </g>
      ))}

      {/* terrasse et piscine */}
      <rect x="90" y="420" width="640" height="10" fill="#3a3029" />
      <path d="M140 430 H700 L740 470 H100Z" fill="url(#vs-pool)" />
      <path d="M140 430 H700 L740 470 H100Z" fill="#ffb547" opacity=".12" />
      {[0, 1, 2, 3].map((i) => (
        <rect key={i} x={200 + i * 120} y={440 + (i % 2) * 10} width={70} height="2" rx="1" fill="#ffd88a" opacity=".45" className="animate-glow" style={{ animationDelay: `${i * 0.7}s` }} />
      ))}
      <rect x="0" y="470" width="800" height="90" fill="url(#vs-ground)" />

      {/* végétation */}
      <g fill="#120d0a">
        <path d="M60 470 C60 420 40 400 52 360 C70 390 78 420 72 470Z" />
        <path d="M30 470 C34 430 14 410 20 380 C38 404 46 430 44 470Z" />
        <ellipse cx="760" cy="455" rx="52" ry="30" />
        <ellipse cx="715" cy="462" rx="34" ry="20" />
      </g>

      {/* capteurs connectés : impulsions */}
      {[
        [300, 252],
        [560, 252],
        [255, 360],
        [620, 360],
      ].map(([x, y], i) => (
        <g key={i}>
          <circle cx={x} cy={y} r="4" fill="#ffc93c" />
          <circle cx={x} cy={y} r="12" fill="none" stroke="#ffc93c" strokeOpacity=".5" className="animate-glow" style={{ animationDelay: `${i * 0.5}s` }} />
        </g>
      ))}
      <path d="M300 252 Q430 150 560 252" fill="none" stroke="#ffc93c" strokeOpacity=".45" strokeWidth="1.5" strokeDasharray="4 8" className="animate-flow" />
      <path d="M255 360 Q440 300 620 360" fill="none" stroke="#ffc93c" strokeOpacity=".35" strokeWidth="1.5" strokeDasharray="4 8" className="animate-flow" />
    </svg>
  );
}
