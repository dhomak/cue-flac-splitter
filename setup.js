#!/usr/bin/env node
'use strict';

// Downloads all bundled dependencies into vendor/ before building.
// Run once: node setup.js
// Then build: npm run build

const fs   = require('fs');
const path = require('path');
const os   = require('os');
const { execSync } = require('child_process');

const ROOT = __dirname;

// ── HTTP helpers ──────────────────────────────────────────────────────────────

function downloadFile(url, dest) {
  return new Promise((resolve, reject) => {
    const tryGet = (u) => {
      const mod = u.startsWith('https:') ? require('https') : require('http');
      mod.get(u, { headers: { 'User-Agent': 'music-tools-setup/1.0' } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          tryGet(res.headers.location);
          return;
        }
        if (res.statusCode !== 200) {
          reject(new Error(`HTTP ${res.statusCode} for ${u}`));
          return;
        }
        const out = fs.createWriteStream(dest);
        res.pipe(out);
        out.on('finish', () => out.close(resolve));
        out.on('error', reject);
        res.on('error', reject);
      }).on('error', reject);
    };
    tryGet(url);
  });
}

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    const tryGet = (u) => {
      const mod = u.startsWith('https:') ? require('https') : require('http');
      mod.get(u, { headers: { 'User-Agent': 'music-tools-setup/1.0' } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          tryGet(res.headers.location);
          return;
        }
        const chunks = [];
        res.on('data', c => chunks.push(c));
        res.on('end', () => {
          try { resolve(JSON.parse(Buffer.concat(chunks).toString())); }
          catch (e) { reject(e); }
        });
        res.on('error', reject);
      }).on('error', reject);
    };
    tryGet(url);
  });
}

// ── ffmpeg / ffprobe ──────────────────────────────────────────────────────────

async function setupFfmpegBinaries() {
  console.log('\n==> ffmpeg / ffprobe');

  const tools = [
    { installer: '@ffmpeg-installer',  binary: 'ffmpeg'  },
    { installer: '@ffprobe-installer', binary: 'ffprobe' },
  ];

  for (const arch of ['arm64', 'x64']) {
    for (const { installer, binary } of tools) {
      const dest = path.join(ROOT, 'vendor', 'bin', arch, binary);
      if (fs.existsSync(dest)) {
        console.log(`    ✓ ${binary} (${arch}) already present`);
        continue;
      }

      const npmPkg = `${installer}/darwin-${arch}`;
      console.log(`    Downloading ${npmPkg}...`);

      // Install into a temp dir so the project's node_modules stay clean
      const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'music-tools-'));
      try {
        execSync(`npm install --prefix "${tmp}" --force "${npmPkg}"`, { stdio: 'pipe' });
        const pkgDir = path.join(tmp, 'node_modules', ...npmPkg.split('/'));
        const src = path.join(pkgDir, binary);
        if (!fs.existsSync(src)) throw new Error(`Binary not found at ${src}`);
        fs.mkdirSync(path.dirname(dest), { recursive: true });
        fs.copyFileSync(src, dest);
        fs.chmodSync(dest, 0o755);
        console.log(`    ✓ ${binary} (${arch})`);
      } catch (e) {
        console.error(`    ✗ ${binary} (${arch}): ${e.message}`);
      } finally {
        fs.rmSync(tmp, { recursive: true, force: true });
      }
    }
  }
}

// ── Python (python-build-standalone) ─────────────────────────────────────────

async function setupPython() {
  console.log('\n==> Python (python-build-standalone)');

  console.log('    Fetching latest release from GitHub...');
  const release = await fetchJson(
    'https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest'
  );
  console.log(`    Release: ${release.tag_name}`);

  const archMap = {
    arm64: 'aarch64-apple-darwin',
    x64:   'x86_64-apple-darwin',
  };

  for (const [arch, pbsArch] of Object.entries(archMap)) {
    const targetDir  = path.join(ROOT, 'vendor', 'python', arch);
    const pythonBin  = path.join(targetDir, 'bin', 'python3');

    if (fs.existsSync(pythonBin)) {
      console.log(`    ✓ Python (${arch}) already present`);
      continue;
    }

    const asset = release.assets.find(a =>
      a.name.includes(pbsArch) &&
      a.name.includes('install_only') &&
      a.name.endsWith('.tar.gz') &&
      !a.name.includes('.sha256')
    );

    if (!asset) {
      console.error(`    ✗ Python (${arch}): no matching asset in release ${release.tag_name}`);
      continue;
    }

    const mb      = Math.round(asset.size / 1024 / 1024);
    const tmpFile = path.join(os.tmpdir(), asset.name);
    console.log(`    Downloading Python (${arch}) — ${mb} MB...`);
    await downloadFile(asset.browser_download_url, tmpFile);

    console.log(`    Extracting...`);
    fs.mkdirSync(targetDir, { recursive: true });
    execSync(`tar -xzf "${tmpFile}" -C "${targetDir}" --strip-components=1`);
    fs.unlinkSync(tmpFile);

    console.log(`    Installing Python packages (${arch})...`);
    execSync(
      `"${pythonBin}" -m pip install --quiet mutagen requests beautifulsoup4 lxml striprtf`,
      { stdio: 'pipe' }
    );

    console.log(`    ✓ Python (${arch}) ready`);
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log('Setting up bundled dependencies for a self-contained build...');

  await setupFfmpegBinaries();
  await setupPython();

  console.log('\n✓ All dependencies ready. Run "npm run build" to build.');
}

main().catch(e => {
  console.error('\nSetup failed:', e.message);
  process.exit(1);
});
