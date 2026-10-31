/** Logo Solea : soleil en dégradé jaune → orange (même dessin que dans l'app). */
export function SunMark({ size = 32, className = "" }: { size?: number; className?: string }) {
  const rays = Array.from({ length: 8 }, (_, i) => {
    const a = (i * Math.PI) / 4 - Math.PI / 2;
    return { x1: 50 + Math.cos(a) * 32, y1: 50 + Math.sin(a) * 32, x2: 50 + Math.cos(a) * 45, y2: 50 + Math.sin(a) * 45 };
  });
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" className={className} aria-hidden="true">
      <defs>
        <linearGradient id="solea-sun" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#FFC93C" />
          <stop offset=".55" stopColor="#F28C1B" />
          <stop offset="1" stopColor="#EE6A1F" />
        </linearGradient>
      </defs>
      <circle cx="50" cy="50" r="22" fill="url(#solea-sun)" />
      {rays.map((r, i) => (
        <line key={i} {...r} stroke="url(#solea-sun)" strokeWidth="7.5" strokeLinecap="round" />
      ))}
    </svg>
  );
}

export function Wordmark({ dark = false, size = 30 }: { dark?: boolean; size?: number }) {
  return (
    <span className="inline-flex items-center gap-2" dir="ltr">
      <SunMark size={size} />
      <span className={`font-extrabold tracking-tight ${dark ? "text-white" : "text-ink"}`} style={{ fontSize: size * 0.7 }}>
        Solea
      </span>
    </span>
  );
}
