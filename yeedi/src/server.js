// API locale lue par la passerelle Solea (HTTP, adresse locale, jeton partagé).
//
//   GET  /robots                      → [{id, name, model, online, state}]
//   POST /robots/:id/command          {action} | {suction} | {water} | {rooms, passes?} | {zone, passes?}
//                                     → {status, error?, robot?}
//
// Copyright (C) 2026 FlowIT Connect
// Ce programme est un logiciel libre : GPL version 3 ou ultérieure (voir LICENSE).

import { createServer } from 'node:http';
import { timingSafeEqual } from 'node:crypto';

const json = (res, code, body) => {
  res.writeHead(code, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body));
};

function authorized(req, token) {
  const given = Buffer.from(String(req.headers.authorization ?? '').replace(/^Bearer\s+/i, ''));
  const want = Buffer.from(token);
  return given.length === want.length && timingSafeEqual(given, want);
}

async function readJson(req) {
  let size = 0;
  const chunks = [];
  for await (const c of req) {
    size += c.length;
    if (size > 4096) throw new Error('trop long');
    chunks.push(c);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
}

/** @param {import('./robots.js').RobotHub} hub */
export function yeediServer(hub, { token, commandTimeoutMs = 15_000 }) {
  return createServer(async (req, res) => {
    try {
      if (!authorized(req, token)) return json(res, 401, { error: 'Jeton invalide' });
      const url = new URL(req.url, 'http://local');
      if (req.method === 'GET' && url.pathname === '/robots') return json(res, 200, hub.list());
      const m = url.pathname.match(/^\/robots\/([^/]{1,128})\/command$/);
      if (req.method === 'POST' && m) {
        let body;
        try {
          body = await readJson(req);
        } catch {
          return json(res, 400, { error: 'Requête invalide' });
        }
        const cmd =
          body.rooms !== undefined ? { rooms: body.rooms, passes: body.passes }
          : body.zone !== undefined ? { zone: body.zone, passes: body.passes }
          : body.water !== undefined ? { water: body.water }
          : body.suction !== undefined ? { suction: body.suction }
          : { action: body.action };
        return json(res, 200, await hub.command(decodeURIComponent(m[1]), cmd, commandTimeoutMs));
      }
      return json(res, 404, { error: 'Introuvable' });
    } catch (e) {
      return json(res, 500, { error: e.message });
    }
  });
}
