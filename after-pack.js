'use strict';

// electron-builder afterPack hook.
// Removes the unused architecture's vendor files from each DMG so both
// arm64 and x64 builds stay lean.

const fs   = require('fs');
const path = require('path');

// electron-builder Arch enum: ia32=0, x64=1, armv7l=2, arm64=3, universal=4
const ARCH_MAP = { 1: 'x64', 3: 'arm64' };

module.exports = async (context) => {
  const archStr = ARCH_MAP[context.arch];
  if (!archStr) return; // universal or other — leave both in place

  const remove = archStr === 'arm64' ? 'x64' : 'arm64';

  const resourcesDir = path.join(
    context.appOutDir,
    'Music Tools.app',
    'Contents',
    'Resources'
  );

  for (const subdir of [`vendor/python/${remove}`, `vendor/bin/${remove}`]) {
    const p = path.join(resourcesDir, subdir);
    if (fs.existsSync(p)) {
      fs.rmSync(p, { recursive: true, force: true });
    }
  }
};
