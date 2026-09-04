// Read-only public-vector interoperability check. No listener, DB, credentials or key generation.
// Usage: node scripts/verify-device-enrollment.mjs /absolute/path/to/pinbook-team-delivery
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { createHash, createPublicKey, verify } from 'node:crypto';
import { isAbsolute, join } from 'node:path';
import { pathToFileURL } from 'node:url';

const backend = process.argv[2];
assert(backend && isAbsolute(backend), 'Supply the approved local backend checkout as an absolute path');
const { deviceEnrollmentMessage } = await import(pathToFileURL(join(backend, 'server/src/device-enrollment.mjs')));
for (const filename of ['team-device-enrollment-v1.json', 'team-device-enrollment-swift-v1.json']) {
  const vector = JSON.parse(fs.readFileSync(new URL(`../Tests/PinbookCoreTests/Fixtures/${filename}`, import.meta.url), 'utf8'));
  const bytes = deviceEnrollmentMessage(vector.challenge);
  assert.equal(bytes.toString('utf8'), vector.message);
  const jwk = vector.publicKey;
  assert.deepEqual(Object.keys(jwk).sort(), ['crv', 'kty', 'x', 'y']);
  const thumb = createHash('sha256').update(JSON.stringify({ crv: jwk.crv, kty: jwk.kty, x: jwk.x, y: jwk.y })).digest('base64url');
  assert.equal(thumb, vector.challenge.keyThumbprint);
  const key = createPublicKey({ key: jwk, format: 'jwk' });
  const signature = Buffer.from(vector.signature, 'base64url');
  assert.equal(signature.length, 64);
  assert.equal(signature.toString('base64url'), vector.signature);
  assert(verify('sha256', bytes, { key, dsaEncoding: 'ieee-p1363' }, signature));
  for (const field of Object.keys(vector.challenge)) {
    const changed = { ...vector.challenge };
    changed[field] = field === 'audience' ? 'https://changed.example'
      : field === 'expiresAt' ? 119999
      : ['nonce', 'challengeId', 'keyThumbprint'].includes(field) ? 'A'.repeat(43) : 'changed';
    assert(!verify('sha256', deviceEnrollmentMessage(changed), { key, dsaEncoding: 'ieee-p1363' }, signature));
  }
  assert(!verify('sha256', Buffer.concat([bytes, Buffer.from('\n')]), { key, dsaEncoding: 'ieee-p1363' }, signature));
  assert(!verify('sha256', createHash('sha256').update(bytes).digest(), { key, dsaEncoding: 'ieee-p1363' }, signature));
  console.log(`${filename}: exact backend bytes/thumbprint, raw signature, nine field mutations, newline and double-hash negatives PASS`);
}
