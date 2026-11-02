import {
  Lightbulb, Cctv, DoorOpen, KeyRound, Radar, Thermometer, Zap, Blinds, Router,
  LayoutDashboard, Workflow, ShieldCheck, Video, Gauge, Server,
  Sparkles, Boxes, BadgeCheck, TrendingUp, Lock, LifeBuoy,
  Home, Building2, Hotel, Briefcase,
  type LucideIcon,
} from "lucide-react";

/** Familles d'appareils (libellés dans messages/*.json › categories). */
export const categoryKeys = ["lighting", "security", "intercom", "access", "sensors", "climate", "energy", "shutters", "gateways"] as const;
export type CategoryKey = (typeof categoryKeys)[number];

export const categoryMeta: Record<CategoryKey, { icon: LucideIcon; hue: string; protocols: string[] }> = {
  lighting: { icon: Lightbulb, hue: "from-amber-200 to-orange-300", protocols: ["Zigbee", "Wi-Fi"] },
  security: { icon: Cctv, hue: "from-sky-200 to-indigo-300", protocols: ["ONVIF", "RTSP", "HTTP/HTTPS", "API", "Zigbee", "Wi-Fi", "Ethernet"] },
  intercom: { icon: DoorOpen, hue: "from-violet-200 to-fuchsia-300", protocols: ["SIP", "RTP", "WebRTC", "ONVIF", "RTSP"] },
  access: { icon: KeyRound, hue: "from-rose-200 to-orange-300", protocols: ["Wi-Fi", "Zigbee", "Bluetooth", "Ethernet"] },
  sensors: { icon: Radar, hue: "from-emerald-200 to-teal-300", protocols: ["Zigbee"] },
  climate: { icon: Thermometer, hue: "from-cyan-200 to-sky-300", protocols: ["Wi-Fi", "Zigbee", "IR"] },
  energy: { icon: Zap, hue: "from-yellow-200 to-amber-300", protocols: ["Wi-Fi", "Zigbee"] },
  shutters: { icon: Blinds, hue: "from-stone-200 to-amber-200", protocols: ["Zigbee", "Wi-Fi"] },
  gateways: { icon: Router, hue: "from-orange-200 to-red-300", protocols: ["Zigbee", "Wi-Fi", "Ethernet", "MQTT"] },
};

export const featureKeys = ["control", "automation", "security", "access", "energy", "local"] as const;
export const featureIcons: Record<(typeof featureKeys)[number], LucideIcon> = {
  control: LayoutDashboard, automation: Workflow, security: ShieldCheck, access: Video, energy: Gauge, local: Server,
};

export const techKeys = ["zigbee", "wifi", "ethernet", "onvif", "rtsp", "sip", "webrtc", "mqtt"] as const;

export const benefitKeys = ["simple", "open", "honest", "scalable", "secure", "support"] as const;
export const benefitIcons: Record<(typeof benefitKeys)[number], LucideIcon> = {
  simple: Sparkles, open: Boxes, honest: BadgeCheck, scalable: TrendingUp, secure: Lock, support: LifeBuoy,
};

export const solutionKeys = ["villa", "apartment", "residence", "business"] as const;
export type SolutionKey = (typeof solutionKeys)[number];
export const solutionIcons: Record<SolutionKey, LucideIcon> = { villa: Home, apartment: Building2, residence: Hotel, business: Briefcase };

export const projectTypes = ["villa", "apartment", "residence", "business", "installation", "security", "intercom", "partnership"] as const;
export type ProjectType = (typeof projectTypes)[number];
export const partnerActivities = ["reseller", "installer", "electrician", "security", "integrator", "developer", "construction", "other"] as const;
