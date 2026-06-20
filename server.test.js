const request = require('supertest');
const { app } = require('./server');

// ── GET / ─────────────────────────────────────────────────────────────────────

describe('GET /', () => {
  it('returns 200 HTML with music_root injected', async () => {
    const res = await request(app).get('/');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/html/);
    // Template variable must be replaced — raw placeholder must not appear
    expect(res.text).not.toContain('{{ music_root }}');
  });
});

// ── GET /api/browse ───────────────────────────────────────────────────────────

describe('GET /api/browse', () => {
  it('lists entries for /', async () => {
    const res = await request(app).get('/api/browse?path=/');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('current', '/');
    expect(Array.isArray(res.body.entries)).toBe(true);
  });

  it('lists entries for the project directory', async () => {
    const res = await request(app).get('/api/browse?path=' + encodeURIComponent(__dirname));
    expect(res.status).toBe(200);
    expect(res.body.entries.some(e => e.name === 'server.js')).toBe(true);
  });

  it('returns 400 for a non-existent path', async () => {
    const res = await request(app).get('/api/browse?path=/does-not-exist-xyzzy');
    expect(res.status).toBe(400);
    expect(res.body).toHaveProperty('error');
  });

  it('omits hidden files from listing', async () => {
    const res = await request(app).get('/api/browse?path=' + encodeURIComponent(__dirname));
    expect(res.status).toBe(200);
    expect(res.body.entries.every(e => !e.name.startsWith('.'))).toBe(true);
  });

  it('returns parent path one level up', async () => {
    const res = await request(app).get('/api/browse?path=/tmp');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('parent', '/');
  });
});

// ── POST /api/* — missing path returns 400 ────────────────────────────────────

const toolEndpoints = [
  '/api/flac-downsample',
  '/api/cue-split',
  '/api/lyrics-fetch',
  '/api/cue-convert',
];

describe('Tool endpoints — missing path', () => {
  toolEndpoints.forEach(endpoint => {
    it(`${endpoint} returns 400 when path is absent`, async () => {
      const res = await request(app)
        .post(endpoint)
        .send({})
        .set('Content-Type', 'application/json');
      expect(res.status).toBe(400);
      expect(res.body).toHaveProperty('error');
    });
  });
});

// ── POST /api/* — valid path returns a job_id ─────────────────────────────────

describe('Tool endpoints — valid path returns job_id', () => {
  it('/api/flac-downsample starts a job', async () => {
    const res = await request(app)
      .post('/api/flac-downsample')
      .send({ path: __dirname })
      .set('Content-Type', 'application/json');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('job_id');
    expect(typeof res.body.job_id).toBe('string');
  });

  it('/api/cue-split starts a job', async () => {
    const res = await request(app)
      .post('/api/cue-split')
      .send({ path: __dirname })
      .set('Content-Type', 'application/json');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('job_id');
  });

  it('/api/lyrics-fetch starts a job', async () => {
    const res = await request(app)
      .post('/api/lyrics-fetch')
      .send({ path: __dirname })
      .set('Content-Type', 'application/json');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('job_id');
  });

  it('/api/cue-convert starts a job', async () => {
    const res = await request(app)
      .post('/api/cue-convert')
      .send({ path: __dirname })
      .set('Content-Type', 'application/json');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('job_id');
  });

  it('/api/rutracker returns 400 when urls is absent', async () => {
    const res = await request(app)
      .post('/api/rutracker')
      .send({})
      .set('Content-Type', 'application/json');
    expect(res.status).toBe(400);
    expect(res.body).toHaveProperty('error');
  });
});

// ── Job lifecycle ─────────────────────────────────────────────────────────────

describe('Job lifecycle', () => {
  let jobId;

  beforeAll(async () => {
    const res = await request(app)
      .post('/api/cue-convert')
      .send({ path: __dirname })
      .set('Content-Type', 'application/json');
    jobId = res.body.job_id;
  });

  it('GET /job/:id/status returns returncode (null while running or int when done)', async () => {
    const res = await request(app).get(`/job/${jobId}/status`);
    expect(res.status).toBe(200);
    const rc = res.body.returncode;
    expect(rc === null || typeof rc === 'number').toBe(true);
  });

  it('GET /job/unknown/status returns 404', async () => {
    const res = await request(app).get('/job/nonexistent1234/status');
    expect(res.status).toBe(404);
  });

  it('POST /job/:id/stop returns success', async () => {
    const res = await request(app).post(`/job/${jobId}/stop`);
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('success', true);
  });

  it('POST /job/unknown/stop returns 404', async () => {
    const res = await request(app).post('/job/nonexistent1234/stop');
    expect(res.status).toBe(404);
  });
});

// ── Lyrics-fetch options pass-through ────────────────────────────────────────

describe('/api/lyrics-fetch options', () => {
  it('accepts workers, delay, overwrite without error', async () => {
    const res = await request(app)
      .post('/api/lyrics-fetch')
      .send({ path: __dirname, workers: 4, delay: 0.5, overwrite: true })
      .set('Content-Type', 'application/json');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('job_id');
  });
});
