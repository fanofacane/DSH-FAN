// SPDX-License-Identifier: AGPL-3.0-or-later
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const dshRequire = createRequire('/opt/dsh/node_modules/@deepseek-ai/dsh/package.json');
const checks = {
  'node-pty': () => new Promise((resolve, reject) => {
    const pty = dshRequire('node-pty').spawn('/bin/sh', ['-c', 'printf PTY_OK; read ack; [ \"$ack\" = ack ]'],
      { name: 'xterm', cols: 80, rows: 24, env: process.env });
    let output = '';
    let acknowledged = false;
    const timer = setTimeout(() => { pty.kill(); reject(new Error('PTY timeout')); }, 15000);
    pty.onData(text => {
      output += text;
      // Keep the terminal alive until its actual output has been read, then
      // send input and check a clean exit. No terminal echo can satisfy this
      // marker before the printf, because the input contains only 'ack'.
      if (!acknowledged && output.includes('PTY_OK')) {
        acknowledged = true;
        pty.write('ack\r');
      }
    });
    pty.onExit(({ exitCode }) => {
      clearTimeout(timer);
      if (exitCode === 0 && output.includes('PTY_OK')) resolve();
      else reject(new Error(`PTY output/exit mismatch: exit=${exitCode} output=${JSON.stringify(output)}`));
    });
  }),
  koffi: () => {
    const libc = dshRequire('koffi').load('/lib/ld-musl-aarch64.so.1');
    try { assert.ok(libc.func('int getpid()')() > 0); }
    finally { libc.unload(); }
  },
  'node:sqlite': () => {
    const { DatabaseSync } = require('node:sqlite');
    const db = new DatabaseSync('/tmp/runtime-probe.sqlite');
    try {
      db.exec('CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY)');
      db.prepare('INSERT OR REPLACE INTO sessions VALUES (?)').run('probe');
      assert.equal(db.prepare('SELECT id FROM sessions WHERE id = ?').get('probe').id, 'probe');
    } finally { db.close(); }
  },
  sharp: async () => {
    const png = await dshRequire('sharp')({ create: {
      width: 1, height: 1, channels: 3, background: '#000'
    } }).png().toBuffer();
    assert.equal(png.subarray(1, 4).toString(), 'PNG');
    assert.equal(png.length > 8, true);
  },
};
(async () => {
  const name = process.argv[2];
  assert.equal(typeof checks[name], 'function');
  console.log(`PROBE module ${name} load BEGIN`);
  await checks[name]();
  console.log(`PROBE module ${name} assertions PASS`);
})().catch(error => {
  // Tests have no credentials. Keep the concrete loader/runtime error.
  console.error(`${error.name}: ${error.message}`);
  process.exitCode = 1;
});
