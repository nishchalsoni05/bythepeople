import Fastify from 'fastify';
import cors from '@fastify/cors';
import { db, initSchema } from './db.js';
import { CONFIG, CATEGORIES, RANKS, BADGES } from './config.js';
import {
  now, DAY, haversineKm, hashPassword, verifyPassword, newToken, ApiError, num,
} from './util.js';
import {
  issueRows, issueRow, issueView, createIssue, supportIssue, withdrawSupport,
  joinEvent, leaveEvent, scheduleEvent, resolveEvent, verifyEvent,
  touchLocation, parseLoc, radiusFor, netaView, netaStats, netaTree, descendantIds,
  userProfile, severityOf, round1,
  resolveArea, resolveScope, leaderInScope, areaTree, scopeSummary,
} from './logic.js';

initSchema();

export function buildApp() {
  const app = Fastify({ logger: false });
  app.register(cors, { origin: true });

  app.setErrorHandler((err, req, reply) => {
    if (err instanceof ApiError) {
      return reply.status(err.status).send({ error: err.message, code: err.code, ...err.extra });
    }
    if (err.validation || err.statusCode === 400) {
      return reply.status(400).send({ error: err.message, code: 'BAD_REQUEST' });
    }
    console.error(err);
    return reply.status(500).send({ error: 'Something went wrong', code: 'SERVER_ERROR' });
  });

  function auth(req) {
    const h = req.headers.authorization || '';
    const token = h.startsWith('Bearer ') ? h.slice(7) : null;
    if (!token) throw new ApiError(401, 'UNAUTHENTICATED', 'Please sign in');
    const row = db.prepare('SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token=?').get(token);
    if (!row) throw new ApiError(401, 'UNAUTHENTICATED', 'Session expired. Please sign in again');
    return row;
  }

  const session = (userId) => {
    const token = newToken();
    db.prepare('INSERT INTO sessions (token,user_id,created_at) VALUES (?,?,?)').run(token, userId, now());
    return token;
  };

  // ---------- meta ----------
  app.get('/health', async () => ({ ok: true, time: now() }));
  app.get('/meta', async () => ({
    config: CONFIG,
    categories: Object.entries(CATEGORIES).map(([key, c]) => ({ key, ...c })),
    ranks: RANKS,
    badges: BADGES,
  }));

  // ---------- auth ----------
  app.post('/auth/register', async (req, reply) => {
    const b = req.body || {};
    const name = String(b.name || '').trim();
    const email = String(b.email || '').trim().toLowerCase();
    const password = String(b.password || '');
    if (name.length < 2) throw new ApiError(400, 'BAD_NAME', 'Please enter your name');
    if (!/^\S+@\S+\.\S+$/.test(email)) throw new ApiError(400, 'BAD_EMAIL', 'Enter a valid email');
    if (password.length < 6) throw new ApiError(400, 'BAD_PASSWORD', 'Password must be at least 6 characters');
    if (db.prepare('SELECT 1 x FROM users WHERE email=?').get(email)) {
      throw new ApiError(409, 'EMAIL_TAKEN', 'An account with this email already exists');
    }
    const { hash, salt } = hashPassword(password);
    const info = db.prepare(`INSERT INTO users (name,email,password_hash,salt,hue,created_at,alert_radius_km) VALUES (?,?,?,?,?,?,?)`)
      .run(name, email, hash, salt, Math.floor(Math.random() * 360), now(), CONFIG.defaultAlertRadiusKm);
    const id = Number(info.lastInsertRowid);
    const user = db.prepare('SELECT * FROM users WHERE id=?').get(id);
    reply.status(201);
    return { token: session(id), user: userProfile(user) };
  });

  app.post('/auth/login', async (req) => {
    const b = req.body || {};
    const email = String(b.email || '').trim().toLowerCase();
    const user = db.prepare('SELECT * FROM users WHERE email=?').get(email);
    if (!user || !verifyPassword(String(b.password || ''), user.password_hash, user.salt)) {
      throw new ApiError(401, 'BAD_CREDENTIALS', 'Wrong email or password');
    }
    return { token: session(user.id), user: userProfile(user) };
  });

  app.post('/auth/logout', async (req) => {
    const h = req.headers.authorization || '';
    if (h.startsWith('Bearer ')) db.prepare('DELETE FROM sessions WHERE token=?').run(h.slice(7));
    return { ok: true };
  });

  // ---------- me ----------
  app.get('/me', async (req) => {
    const user = auth(req);
    const unread = db.prepare('SELECT COUNT(*) c FROM notifications WHERE user_id=? AND read=0').get(user.id).c;
    return { user: userProfile(user), unread };
  });

  app.patch('/me', async (req) => {
    const user = auth(req);
    const b = req.body || {};
    if (b.name !== undefined) {
      const n = String(b.name).trim();
      if (n.length < 2) throw new ApiError(400, 'BAD_NAME', 'Name is too short');
      db.prepare('UPDATE users SET name=? WHERE id=?').run(n, user.id);
    }
    if (b.volunteer !== undefined) db.prepare('UPDATE users SET volunteer=? WHERE id=?').run(b.volunteer ? 1 : 0, user.id);
    if (b.alertRadiusKm !== undefined) {
      const r = num(b.alertRadiusKm);
      if (!Number.isFinite(r) || r < 1 || r > 25) throw new ApiError(400, 'BAD_RADIUS', 'Radius must be between 1 and 25 km');
      db.prepare('UPDATE users SET alert_radius_km=? WHERE id=?').run(r, user.id);
    }
    if (b.homeLat !== undefined && b.homeLng !== undefined) {
      const l = parseLoc(b.homeLat, b.homeLng, 'home location');
      db.prepare('UPDATE users SET home_lat=?, home_lng=? WHERE id=?').run(l.lat, l.lng, user.id);
    }
    return { user: userProfile(db.prepare('SELECT * FROM users WHERE id=?').get(user.id)) };
  });

  app.post('/me/location', async (req) => {
    const user = auth(req);
    const ok = touchLocation(user, req.body?.lat, req.body?.lng, false);
    return { ok };
  });

  app.get('/me/activity', async (req) => {
    const user = auth(req);
    const { type = 'reports', lat, lng } = req.query;
    const loc = Number.isFinite(num(lat)) && Number.isFinite(num(lng)) ? { lat: num(lat), lng: num(lng) } : null;
    let rows;
    if (type === 'reports') rows = issueRows('WHERE i.reporter_id=? ORDER BY i.created_at DESC', user.id);
    else if (type === 'supported') {
      rows = issueRows('WHERE i.id IN (SELECT issue_id FROM supports WHERE user_id=?) AND i.reporter_id!=? ORDER BY i.created_at DESC', user.id, user.id);
    } else if (type === 'events') {
      rows = issueRows('WHERE i.id IN (SELECT issue_id FROM volunteers WHERE user_id=?) ORDER BY COALESCE(i.scheduled_at, i.created_at) ASC', user.id);
    } else throw new ApiError(400, 'BAD_TYPE', 'Unknown activity type');
    return { items: rows.map((r) => issueView(r, user, loc)) };
  });

  // ---------- notifications ----------
  app.get('/notifications', async (req) => {
    const user = auth(req);
    const items = db.prepare('SELECT * FROM notifications WHERE user_id=? ORDER BY created_at DESC, id DESC LIMIT 100').all(user.id)
      .map((n) => ({ id: n.id, type: n.type, title: n.title, body: n.body, issueId: n.issue_id, read: !!n.read, createdAt: n.created_at }));
    const unread = items.filter((n) => !n.read).length;
    return { items, unread };
  });

  app.post('/notifications/read', async (req) => {
    const user = auth(req);
    const ids = Array.isArray(req.body?.ids) ? req.body.ids.map(Number).filter(Number.isFinite) : null;
    if (ids && ids.length) {
      db.prepare(`UPDATE notifications SET read=1 WHERE user_id=? AND id IN (${ids.map(() => '?').join(',')})`).run(user.id, ...ids);
    } else {
      db.prepare('UPDATE notifications SET read=1 WHERE user_id=?').run(user.id);
    }
    return { ok: true };
  });

  // ---------- issues & events ----------
  app.get('/issues', async (req) => {
    const user = auth(req);
    const q = req.query;
    const la = num(q.lat); const ln = num(q.lng);
    const loc = Number.isFinite(la) && Number.isFinite(ln) ? { lat: la, lng: ln } : null;
    if (loc) touchLocation(user, loc.lat, loc.lng, false);
    const phase = q.phase || 'issue'; // issue | event | closed | all
    const statuses = {
      issue: ['open'],
      event: ['event', 'in_progress', 'pending_verification'],
      closed: ['closed'],
    }[phase];
    let rows = statuses
      ? issueRows(`WHERE i.status IN (${statuses.map(() => '?').join(',')})`, ...statuses)
      : issueRows();
    const sc = resolveScope(q, user, loc);
    if (sc.area) {
      const col = { city: 'city_id', state: 'state_id', region: 'region_id' }[sc.scope];
      rows = rows.filter((r) => r[col] === sc.area.id);
    }
    if (q.category) rows = rows.filter((r) => r.category === q.category);
    if (q.politicianId) {
      const ids = new Set(descendantIds(Number(q.politicianId)));
      rows = rows.filter((r) => ids.has(r.politician_id));
    }
    if (q.q) {
      const needle = String(q.q).toLowerCase();
      rows = rows.filter((r) => r.title.toLowerCase().includes(needle) || (r.description || '').toLowerCase().includes(needle));
    }
    let items = rows.map((r) => issueView(r, user, loc));
    const radius = num(q.radiusKm);
    if (loc && Number.isFinite(radius)) items = items.filter((i) => i.distanceKm <= radius);
    const sev = { critical: 4, high: 3, medium: 2, low: 1 };
    const sort = q.sort || (phase === 'event' ? 'soon' : 'nearby');
    if (sort === 'nearby' && loc) items.sort((a, b) => a.distanceKm - b.distanceKm);
    else if (sort === 'severity') items.sort((a, b) => b.severityScore - a.severityScore || sev[b.severity] - sev[a.severity]);
    else if (sort === 'new') items.sort((a, b) => b.createdAt - a.createdAt);
    else if (sort === 'soon') items.sort((a, b) => (a.scheduledAt ?? Infinity) - (b.scheduledAt ?? Infinity));
    return { items };
  });

  // Similar open issues near a pin (duplicate prevention)
  app.get('/issues/similar', async (req) => {
    const user = auth(req);
    const loc = parseLoc(req.query.lat, req.query.lng, 'issue location');
    const rows = issueRows("WHERE i.status IN ('open','event','in_progress') AND i.category=?", req.query.category || '');
    const items = rows
      .map((r) => issueView(r, user, loc))
      .filter((i) => haversineKm(loc.lat, loc.lng, i.lat, i.lng) <= CONFIG.duplicateRadiusKm)
      .sort((a, b) => a.distanceKm - b.distanceKm);
    return { items };
  });

  app.get('/issues/:id', async (req) => {
    const user = auth(req);
    const row = issueRow(Number(req.params.id));
    if (!row) throw new ApiError(404, 'NOT_FOUND', 'Issue not found');
    const la = num(req.query.lat); const ln = num(req.query.lng);
    const loc = Number.isFinite(la) && Number.isFinite(ln) ? { lat: la, lng: ln } : null;
    return { issue: issueView(row, user, loc, true) };
  });

  app.post('/issues', async (req, reply) => {
    const user = auth(req);
    const out = createIssue(user, req.body || {});
    reply.status(201);
    return out;
  });

  app.post('/issues/:id/support', async (req) => supportIssue(auth(req), Number(req.params.id), req.body || {}));
  app.delete('/issues/:id/support', async (req) => withdrawSupport(auth(req), Number(req.params.id)));

  // events share the issue table
  app.get('/events', async (req) => {
    const user = auth(req);
    const la = num(req.query.lat); const ln = num(req.query.lng);
    const loc = Number.isFinite(la) && Number.isFinite(ln) ? { lat: la, lng: ln } : null;
    const rows = issueRows("WHERE i.status IN ('event','in_progress','pending_verification') ORDER BY COALESCE(i.scheduled_at, i.created_at)");
    return { items: rows.map((r) => issueView(r, user, loc)) };
  });
  app.post('/events/:id/join', async (req) => joinEvent(auth(req), Number(req.params.id), req.body || {}));
  app.delete('/events/:id/join', async (req) => leaveEvent(auth(req), Number(req.params.id)));
  app.post('/events/:id/schedule', async (req) => scheduleEvent(auth(req), Number(req.params.id), req.body || {}));
  app.post('/events/:id/resolve', async (req) => resolveEvent(auth(req), Number(req.params.id), req.body || {}));
  app.post('/events/:id/verify', async (req) => verifyEvent(auth(req), Number(req.params.id), req.body || {}));

  // ---------- netas ----------
  app.get('/netas', async (req) => {
    const user = auth(req);
    const { q, party, level, constituency } = req.query;
    const sc = resolveScope(req.query, user);
    let rows = db.prepare('SELECT * FROM politicians ORDER BY id').all().filter((p) => leaderInScope(p, sc));
    if (party) rows = rows.filter((p) => p.party === party);
    if (level) rows = rows.filter((p) => p.level === level);
    if (constituency) rows = rows.filter((p) => p.constituency === constituency);
    if (q) {
      const n = String(q).toLowerCase();
      rows = rows.filter((p) => p.name.toLowerCase().includes(n) || p.constituency.toLowerCase().includes(n) || p.party.toLowerCase().includes(n));
    }
    const parties = [...new Set(db.prepare('SELECT party FROM politicians').all().filter((p) => leaderInScope(p, sc)).map((p) => p.party))].sort();
    return { items: rows.map((p) => netaView(p)), parties, scope: sc.scope, area: sc.area ? { id: sc.area.id, name: sc.area.name } : null };
  });

  app.get('/netas/tree', async (req) => {
    const user = auth(req);
    return { roots: netaTree(resolveScope(req.query, user)) };
  });

  // ---------- geography ----------
  app.get('/geo/areas', async (req) => {
    auth(req);
    return { regions: areaTree() };
  });

  app.get('/geo/resolve', async (req) => {
    auth(req);
    const l = parseLoc(req.query.lat, req.query.lng);
    return resolveArea(l.lat, l.lng);
  });

  app.get('/geo/summary', async (req) => {
    const user = auth(req);
    const la = num(req.query.lat); const ln = num(req.query.lng);
    const loc = Number.isFinite(la) && Number.isFinite(ln) ? { lat: la, lng: ln } : null;
    return scopeSummary(resolveScope(req.query, user, loc));
  });

  app.get('/netas/:id', async (req) => {
    const user = auth(req);
    const p = db.prepare('SELECT * FROM politicians WHERE id=?').get(Number(req.params.id));
    if (!p) throw new ApiError(404, 'NOT_FOUND', 'Politician not found');
    const ids = descendantIds(p.id);
    const rows = issueRows(`WHERE i.politician_id IN (${ids.map(() => '?').join(',')}) ORDER BY i.created_at DESC`, ...ids);
    const items = rows.map((r) => issueView(r, user));
    const children = db.prepare('SELECT * FROM politicians WHERE parent_id=?').all(p.id).map((c) => netaView(c));
    return {
      neta: netaView(p),
      children,
      openIssues: items.filter((i) => i.status !== 'closed'),
      resolvedIssues: items.filter((i) => i.status === 'closed'),
    };
  });

  return app;
}

if (process.argv[1] && process.argv[1].endsWith('server.js')) {
  const count = db.prepare('SELECT COUNT(*) c FROM politicians').get().c;
  if (!count) console.warn('Database is empty. Run `npm run seed` first.');
  const port = Number(process.env.PORT || 3000);
  buildApp().listen({ port, host: '0.0.0.0' }).then(() => {
    console.log(`By the People API listening on http://localhost:${port}`);
  });
}
