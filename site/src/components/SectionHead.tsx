import type { ReactNode } from "react";
import { Reveal } from "./Reveal";

export function SectionHead({ eyebrow, title, text, center = false, dark = false, children }: { eyebrow?: string; title: string; text?: string; center?: boolean; dark?: boolean; children?: ReactNode }) {
  return (
    <Reveal className={`max-w-3xl ${center ? "mx-auto text-center" : ""}`}>
      {eyebrow && <p className={`eyebrow ${dark ? "!text-amber" : ""}`}>{eyebrow}</p>}
      <h2 className={`h-section mt-4 ${dark ? "text-white" : ""}`}>{title}</h2>
      {text && <p className={`mt-5 text-lg leading-relaxed ${dark ? "text-white/65" : "text-ink-soft"}`}>{text}</p>}
      {children}
    </Reveal>
  );
}
