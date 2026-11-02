import type { ReactNode } from "react";

// La balise <html> est posée par app/[locale]/layout.tsx (langue et sens d'écriture).
export default function RootLayout({ children }: { children: ReactNode }) {
  return children;
}
