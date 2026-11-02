import localFont from "next/font/local";

export const manrope = localFont({
  variable: "--font-manrope",
  display: "swap",
  src: [
    { path: "../fonts/Manrope-Regular.ttf", weight: "400" },
    { path: "../fonts/Manrope-Medium.ttf", weight: "500" },
    { path: "../fonts/Manrope-SemiBold.ttf", weight: "600" },
    { path: "../fonts/Manrope-Bold.ttf", weight: "700" },
    { path: "../fonts/Manrope-ExtraBold.ttf", weight: "800" },
  ],
});

export const plexArabic = localFont({
  variable: "--font-arabic",
  display: "swap",
  preload: false,
  src: [
    { path: "../fonts/IBMPlexSansArabic-Regular.ttf", weight: "400" },
    { path: "../fonts/IBMPlexSansArabic-Medium.ttf", weight: "500" },
    { path: "../fonts/IBMPlexSansArabic-SemiBold.ttf", weight: "600" },
    { path: "../fonts/IBMPlexSansArabic-Bold.ttf", weight: "700" },
  ],
});
