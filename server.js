const express = require('express');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');

const app = express();
const PORT = 3000;

app.use(express.json());

// Music root — override via MUSIC_ROOT env var
const MUSIC_ROOT = process.env.MUSIC_ROOT || os.homedir();

// Script directory — works both in dev and inside packaged .app
const SCRIPT_DIR = (() => {
  if (process.resourcesPath && fs.existsSync(path.join(process.resourcesPath, 'scripts'))) {
    return path.join(process.resourcesPath, 'scripts');
  }
  return __dirname;
})();

// Bundled vendor directory (ffmpeg/ffprobe binaries + Python)
const ARCH = process.arch === 'arm64' ? 'arm64' : 'x64';

const VENDOR_DIR = (() => {
  if (process.resourcesPath) {
    const p = path.join(process.resourcesPath, 'vendor');
    if (fs.existsSync(p)) return p;
  }
  const p = path.join(__dirname, 'vendor');
  return fs.existsSync(p) ? p : null;
})();

const BUNDLED_PYTHON = (() => {
  if (VENDOR_DIR) {
    const p = path.join(VENDOR_DIR, 'python', ARCH, 'bin', 'python3');
    if (fs.existsSync(p)) return p;
  }
  // Dev fallbacks when vendor/ hasn't been set up yet
  for (const p of [
    path.join(__dirname, 'venv', 'bin', 'python3'),
    '/opt/homebrew/bin/python3',
    '/usr/local/bin/python3',
  ]) {
    if (fs.existsSync(p)) return p;
  }
  return 'python3';
})();

// macOS GUI apps don't inherit shell PATH — inject bundled binaries and Homebrew paths
const SPAWN_ENV = {
  ...process.env,
  PATH: [
    VENDOR_DIR ? path.join(VENDOR_DIR, 'bin', ARCH) : null,
    '/opt/homebrew/bin',
    '/opt/homebrew/sbin',
    '/usr/local/bin',
    '/usr/bin',
    '/bin',
    '/usr/sbin',
    '/sbin',
    process.env.PATH || '',
  ].filter(Boolean).join(':'),
};

// ── Job management ────────────────────────────────────────────────────────────

const jobs = new Map();

function createJob(proc) {
  const jobId = crypto.randomBytes(8).toString('hex');
  const job = { proc, lines: [], returncode: null, done: false, subscribers: new Set() };
  jobs.set(jobId, job);

  const pushLine = (line) => {
    job.lines.push(line);
    job.subscribers.forEach(res => res.write(`data: ${line}\n\n`));
  };

  const handleData = (data) =>
    data.toString().split('\n').forEach(l => { if (l) pushLine(l); });

  proc.stdout.on('data', handleData);
  proc.stderr.on('data', handleData);

  const finish = (code) => {
    job.returncode = code ?? 1;
    job.done = true;
    job.subscribers.forEach(res => { res.write('event: done\ndata: \n\n'); res.end(); });
    job.subscribers.clear();
    setTimeout(() => jobs.delete(jobId), 300_000);
  };
  proc.on('close', finish);
  proc.on('error', (err) => { pushLine(`[ERROR] ${err.message}`); finish(1); });

  return jobId;
}

// ── Main app ──────────────────────────────────────────────────────────────────

// Serve new index.html with template variables replaced
app.get('/', (req, res) => {
  try {
    const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf-8')
      .replace(/\{\{ music_root \}\}/g, MUSIC_ROOT);
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.send(html);
  } catch (err) {
    res.status(500).send('Error loading app: ' + err.message);
  }
});

app.get('/login',  (req, res) => res.sendFile(path.join(__dirname, 'login.html')));
app.get('/logout', (req, res) => res.redirect('/login'));

// Static assets (tweaks-panel.jsx etc.)
app.use(express.static(path.join(__dirname, 'public')));

// ── Directory browser ─────────────────────────────────────────────────────────

// Accepts any absolute path. Returns: { current, parent, entries: [{ name, is_dir, path }] }
app.get('/api/browse', (req, res) => {
  const reqPath = req.query.path || '/';
  const absPath = path.isAbsolute(reqPath) ? reqPath : path.resolve(MUSIC_ROOT, reqPath);
  const parent  = path.dirname(absPath);

  try {
    const items = fs.readdirSync(absPath, { withFileTypes: true });
    const entries = items
      .filter(item => !item.name.startsWith('.'))
      .sort((a, b) => {
        if (a.isDirectory() !== b.isDirectory()) return a.isDirectory() ? -1 : 1;
        return a.name.localeCompare(b.name);
      })
      .map(item => ({
        name:   item.name,
        is_dir: item.isDirectory(),
        path:   path.join(absPath, item.name),
      }));
    res.json({ current: absPath, parent, entries });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// ── Job streaming ─────────────────────────────────────────────────────────────

// SSE stream — replays buffered lines then forwards live output
app.get('/stream/:jobId', (req, res) => {
  const job = jobs.get(req.params.jobId);
  if (!job) return res.status(404).end();

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders();

  job.lines.forEach(line => res.write(`data: ${line}\n\n`));

  if (job.done) {
    res.write('event: done\ndata: \n\n');
    res.end();
    return;
  }

  job.subscribers.add(res);
  req.on('close', () => job.subscribers.delete(res));
});

app.get('/job/:jobId/status', (req, res) => {
  const job = jobs.get(req.params.jobId);
  if (!job) return res.status(404).json({ error: 'Job not found' });
  res.json({ returncode: job.returncode });
});

app.post('/job/:jobId/stop', (req, res) => {
  const job = jobs.get(req.params.jobId);
  if (!job) return res.status(404).json({ error: 'Job not found' });
  if (job.proc && !job.proc.killed) job.proc.kill('SIGTERM');
  res.json({ success: true });
});

// ── Tool endpoints ────────────────────────────────────────────────────────────

app.post('/api/flac-downsample', (req, res) => {
  const { path: dir, replace, output_path } = req.body;
  if (!dir) return res.status(400).json({ error: 'path required' });
  const args = [path.join(SCRIPT_DIR, 'flac_downsampler.sh')];
  if (replace) { args.push('--replace'); args.push('--yes'); }
  args.push(dir);
  if (output_path) args.push(output_path);
  res.json({ job_id: createJob(spawn('bash', args, { env: SPAWN_ENV })) });
});

app.post('/api/cue-split', (req, res) => {
  const { path: dir, to_root, delete_orig, overwrite, dry_run } = req.body;
  if (!dir) return res.status(400).json({ error: 'path required' });
  const args = [path.join(SCRIPT_DIR, 'split-cue-unicode.pl')];
  if (to_root)     args.push('--to-root');
  if (delete_orig) args.push('--delete');
  if (overwrite)   args.push('--overwrite-final');
  if (dry_run)     args.push('--dry-run');
  args.push(dir);
  res.json({ job_id: createJob(spawn('perl', args, { env: SPAWN_ENV })) });
});

app.post('/api/lyrics-fetch', (req, res) => {
  const { path: dir } = req.body;
  if (!dir) return res.status(400).json({ error: 'path required' });
  const proc = spawn(BUNDLED_PYTHON, ['-u', path.join(SCRIPT_DIR, 'audio_lyrics_fetcher.py'), dir], { env: SPAWN_ENV });
  res.json({ job_id: createJob(proc) });
});

app.post('/api/rutracker', (req, res) => {
  const { urls, username, password } = req.body;
  if (!urls) return res.status(400).json({ error: 'urls required' });
  const tempFile = path.join(os.tmpdir(), `.rt_urls_${Date.now()}.txt`);
  fs.writeFileSync(tempFile, urls, 'utf-8');
  const pyLibsDir = path.join(process.resourcesPath || __dirname, 'pylibs');
  const env = { ...SPAWN_ENV, PYTHONPATH: pyLibsDir };
  if (username) env.RT_USERNAME = username;
  if (password) env.RT_PASSWORD = password;
  const proc = spawn(BUNDLED_PYTHON, ['-u', path.join(SCRIPT_DIR, 'rutracker_scraper.py'), tempFile], { env });
  proc.on('close', () => { try { fs.unlinkSync(tempFile); } catch (_) {} });
  res.json({ job_id: createJob(proc) });
});

app.post('/api/cue-convert', (req, res) => {
  const { path: dir } = req.body;
  if (!dir) return res.status(400).json({ error: 'path required' });
  const proc = spawn('bash', [path.join(SCRIPT_DIR, 'cue_converter.sh'), dir], { env: SPAWN_ENV });
  res.json({ job_id: createJob(proc) });
});

// ── Start ─────────────────────────────────────────────────────────────────────

if (require.main === module) {
  app.listen(PORT, () => console.log(`Music Tools running at http://localhost:${PORT}`));
} else {
  module.exports.start = (callback) => {
    app.listen(PORT, () => {
      console.log(`Music Tools running at http://localhost:${PORT}`);
      if (callback) callback(PORT);
    });
  };
}
