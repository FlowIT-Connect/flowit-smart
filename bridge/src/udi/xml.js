// Petit lecteur XML sans dépendance, suffisant pour les réponses SOAP ONVIF et WS-Discovery.
// Les préfixes d'espace de noms sont ignorés : on cherche les éléments par leur nom local
// (« Profiles » pour « trt:Profiles »), ce qui évite de dépendre des préfixes de chaque fabricant.

const ENTITIES = { lt: '<', gt: '>', amp: '&', quot: '"', apos: "'" };

export function decodeEntities(s) {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => {
    if (e[0] === '#') {
      const code = e[1] === 'x' || e[1] === 'X' ? Number.parseInt(e.slice(2), 16) : Number.parseInt(e.slice(1), 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : m;
    }
    return ENTITIES[e.toLowerCase()] ?? m;
  });
}

export function escapeXml(s) {
  return String(s).replace(/[<>&"']/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;' })[c]);
}

const localName = (qname) => qname.slice(qname.indexOf(':') + 1);

/**
 * @typedef {{name:string, attrs:Record<string,string>, children:XmlNode[], text:string}} XmlNode
 * @returns {XmlNode} nœud racine fictif (« #document »)
 */
export function parseXml(xml) {
  const root = { name: '#document', attrs: {}, children: [], text: '' };
  const stack = [root];
  let i = 0;
  const n = xml.length;
  while (i < n) {
    const lt = xml.indexOf('<', i);
    const textEnd = lt === -1 ? n : lt;
    if (textEnd > i) stack[stack.length - 1].text += decodeEntities(xml.slice(i, textEnd));
    if (lt === -1) break;
    if (xml.startsWith('<!--', lt)) {
      const end = xml.indexOf('-->', lt + 4);
      i = end === -1 ? n : end + 3;
      continue;
    }
    if (xml.startsWith('<![CDATA[', lt)) {
      const end = xml.indexOf(']]>', lt + 9);
      stack[stack.length - 1].text += xml.slice(lt + 9, end === -1 ? n : end);
      i = end === -1 ? n : end + 3;
      continue;
    }
    if (xml.startsWith('<?', lt) || xml.startsWith('<!', lt)) {
      const end = xml.indexOf('>', lt);
      i = end === -1 ? n : end + 1;
      continue;
    }
    const gt = xml.indexOf('>', lt);
    if (gt === -1) throw new Error('XML invalide : balise non fermée');
    const raw = xml.slice(lt + 1, gt);
    i = gt + 1;
    if (raw.startsWith('/')) {
      const name = localName(raw.slice(1).trim());
      // Remonte jusqu'à l'élément correspondant (tolère un document légèrement mal formé).
      for (let k = stack.length - 1; k > 0; k--) {
        if (stack[k].name === name) {
          stack.length = k;
          break;
        }
      }
      continue;
    }
    const selfClosing = raw.endsWith('/');
    const body = selfClosing ? raw.slice(0, -1) : raw;
    const m = /^\s*([^\s/>]+)/.exec(body);
    if (!m) continue;
    const node = { name: localName(m[1]), attrs: {}, children: [], text: '' };
    const attrRe = /([^\s=]+)\s*=\s*("([^"]*)"|'([^']*)')/g;
    let a;
    const rest = body.slice(m[0].length);
    while ((a = attrRe.exec(rest))) node.attrs[localName(a[1])] = decodeEntities(a[3] ?? a[4] ?? '');
    stack[stack.length - 1].children.push(node);
    if (!selfClosing) stack.push(node);
  }
  return root;
}

/** Tous les descendants portant ce nom local (parcours en profondeur, ordre du document). */
export function findAll(node, name) {
  const out = [];
  const walk = (n) => {
    for (const c of n.children) {
      if (c.name === name) out.push(c);
      walk(c);
    }
  };
  if (node) walk(node);
  return out;
}

export function find(node, name) {
  if (!node) return null;
  for (const c of node.children) {
    if (c.name === name) return c;
    const deep = find(c, name);
    if (deep) return deep;
  }
  return null;
}

/** Texte (sans espaces autour) du premier descendant de ce nom, ou null. */
export function textOf(node, name) {
  const f = name ? find(node, name) : node;
  if (!f) return null;
  const t = f.text.trim();
  return t || null;
}

/** Chemin de noms locaux : path(n, 'Capabilities', 'Media', 'XAddr'). */
export function path(node, ...names) {
  let cur = node;
  for (const name of names) {
    cur = find(cur, name);
    if (!cur) return null;
  }
  return cur;
}
