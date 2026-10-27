import fs from 'node:fs';

// A dependency-free, stored ZIP fixture containing a harmless shell executable.
const name = Buffer.from('V2bX');
const body = Buffer.from('#!/usr/bin/env bash\n[[ ${1:-} == version ]] || exit 1\necho "V2bX test-new"\n');
let crc = 0xffffffff;
for (const byte of body) {
  crc ^= byte;
  for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
}
crc = (crc ^ 0xffffffff) >>> 0;
const local = Buffer.alloc(30);
local.writeUInt32LE(0x04034b50, 0);
local.writeUInt16LE(20, 4);
local.writeUInt32LE(crc, 14);
local.writeUInt32LE(body.length, 18);
local.writeUInt32LE(body.length, 22);
local.writeUInt16LE(name.length, 26);
const central = Buffer.alloc(46);
central.writeUInt32LE(0x02014b50, 0);
central.writeUInt16LE(20, 4);
central.writeUInt16LE(20, 6);
central.writeUInt32LE(crc, 16);
central.writeUInt32LE(body.length, 20);
central.writeUInt32LE(body.length, 24);
central.writeUInt16LE(name.length, 28);
const end = Buffer.alloc(22);
end.writeUInt32LE(0x06054b50, 0);
end.writeUInt16LE(1, 8);
end.writeUInt16LE(1, 10);
end.writeUInt32LE(central.length + name.length, 12);
end.writeUInt32LE(local.length + name.length + body.length, 16);
fs.writeFileSync(process.argv[2], Buffer.concat([local, name, body, central, name, end]));
