// Validation d'une valeur de commande selon la capacité déclarée (liste blanche, §7).

/**
 * @param {{capability_key:string,type:string,writable:boolean,metadata:object}} cap
 * @param {unknown} value
 * @returns {string|null} message d'erreur, ou null si la valeur est acceptable
 */
export function validateValue(cap, value) {
  if (!cap) return 'Capacité non prise en charge par cet appareil';
  if (!cap.writable || cap.type === 'sensor') return 'Capacité en lecture seule';
  const meta = cap.metadata ?? {};
  switch (cap.type) {
    case 'boolean':
      return typeof value === 'boolean' ? null : 'Valeur booléenne attendue';
    case 'number': {
      if (typeof value !== 'number' || !Number.isFinite(value)) return 'Valeur numérique attendue';
      if (meta.min != null && value < meta.min) return `Valeur inférieure au minimum (${meta.min})`;
      if (meta.max != null && value > meta.max) return `Valeur supérieure au maximum (${meta.max})`;
      return null;
    }
    case 'enum':
      return Array.isArray(meta.options) && meta.options.includes(value) ? null : 'Option non prise en charge';
    case 'color':
      return typeof value === 'string' && /^#[0-9a-fA-F]{6}$/.test(value) ? null : 'Couleur #RRGGBB attendue';
    default:
      return 'Type de capacité non pilotable';
  }
}
