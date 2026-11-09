import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { parseConfig, redact } from '../src/diag_dahua.js';

describe('Diagnostic Dahua', () => {
  it('lit le réglage RTSP renvoyé par configManager', () => {
    const cfg = parseConfig('table.RTSP.Enable=false\r\ntable.RTSP.Port=554\r\n');
    assert.equal(cfg['RTSP.Enable'], 'false');
    assert.equal(cfg['RTSP.Port'], '554');
  });

  it('ne laisse jamais passer le code de sécurité', () => {
    const b64 = Buffer.from('admin:TEST1234').toString('base64');
    const out = redact(`rtsp://admin:TEST1234@1.2.3.4/x&authbasic=${b64} pass=TEST1234`, ['TEST1234']);
    assert.doesNotMatch(out, /TEST1234/);
    assert.ok(!out.includes(b64));
  });
});
