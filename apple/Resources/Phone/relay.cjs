#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later
// Adapted from this project's Android PhoneGuest.kt; iOS uses TCP only.
// No tools or credentials are written to stdout/stderr.
'use strict'
const fs = require('node:fs')
const net = require('node:net')
let cfg
try {
  cfg = JSON.parse(fs.readFileSync(process.argv[2] || '/var/lib/dsh-app/phone/bridge.json', 'utf8'))
  if (cfg.v !== 1 || !Number.isInteger(cfg.tcpPort) || cfg.tcpPort < 1 || cfg.tcpPort > 65535 || typeof cfg.token !== 'string' || cfg.token.length < 32) throw new Error('invalid configuration')
} catch (_) {
  process.stderr.write('[phone-relay] configuration unavailable\n')
  process.exit(1)
}
const socket = net.connect({host: '127.0.0.1', port: cfg.tcpPort})
const timeout = setTimeout(() => socket.destroy(), 3000)
process.stdout.on('error', () => process.exit(1))
socket.once('connect', () => {
  clearTimeout(timeout)
  socket.setNoDelay(true)
  socket.write(JSON.stringify({dshPhone: 1, token: cfg.token}) + '\n')
  process.stdin.pipe(socket)
  socket.pipe(process.stdout)
})
socket.on('error', () => { process.stderr.write('[phone-relay] bridge unavailable\n'); process.exit(1) })
// Let stdout drain, including the final MCP reply. An immediate process.exit
// here truncates replies larger than the host pipe's remaining capacity.
socket.on('close', () => { clearTimeout(timeout); process.stdin.destroy(); process.exitCode = 0 })
