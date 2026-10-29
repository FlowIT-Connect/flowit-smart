// Encodeur PNG minimal (RVB 8 bits) : sert à l'image de la caméra du simulateur.

import { crc32, deflateSync } from 'node:zlib';

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body) >>> 0);
  return Buffer.concat([len, body, crc]);
}

/**
 * @param {number} width
 * @param {number} height
 * @param {(x:number, y:number) => [number, number, number]} pixel
 */
export function encodePng(width, height, pixel) {
  const raw = Buffer.alloc((width * 3 + 1) * height);
  let o = 0;
  for (let y = 0; y < height; y++) {
    raw[o++] = 0; // filtre « None »
    for (let x = 0; x < width; x++) {
      const [r, g, b] = pixel(x, y);
      raw[o++] = r;
      raw[o++] = g;
      raw[o++] = b;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // profondeur
  ihdr[9] = 2; // RVB
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

/** Image de caméra simulée : une scène chaude traversée par une silhouette qui bouge. */
export function simulatedFrame(t = Date.now(), width = 320, height = 180) {
  const pos = ((t / 40) % (width + 60)) - 30;
  return encodePng(width, height, (x, y) => {
    const sky = y < height * 0.55;
    let r = sky ? 250 - y * 0.4 : 120 - (y - height * 0.55) * 0.3;
    let g = sky ? 190 - y * 0.5 : 92 - (y - height * 0.55) * 0.2;
    let b = sky ? 120 - y * 0.3 : 70;
    if (Math.abs(x - pos) < 9 && y > height * 0.35 && y < height * 0.8) [r, g, b] = [40, 36, 34];
    if (y < 14 && x > width - 46 && x < width - 8) [r, g, b] = [226, 59, 46]; // pastille « REC »
    return [r, g, b].map((v) => Math.max(0, Math.min(255, Math.round(v))));
  });
}
