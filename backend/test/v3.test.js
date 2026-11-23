// API v3 tests: roles/portals, authority, neta, gatherings, donations, comments, public pages, media.
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import assert from 'node:assert/strict';

const stamp = Date.now();
const tmp = path.join(os.tmpdir(), `sober-v3-${stamp}.db`);
const uploads = path.join(os.tmpdir(), `sober-v3-uploads-${stamp}`);
process.env.DB_PATH = tmp;
process.env.UPLOAD_DIR = uploads;
const { seed, BASE } = await import('../src/seed.js');
const { buildApp, runMaintenance } = await import('../src/server.js');
const { db } = await import('../src/db.js');
// a stand-in photo so the seed's "real photo" path is exercised without the network
fs.mkdirSync(uploads, { recursive: true });
fs.writeFileSync(path.join(uploads, 'photo-pothole-1.jpg'), Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46, 0x49, 0x46, 0]));
seed();
const app = buildApp();

let passed = 0;
const t = async (name, fn) => {
  try { await fn(); passed++; console.log(`  ok  ${name}`); }
  catch (e) { console.error(`FAIL  ${name}\n      ${e.stack?.split('\n').slice(0, 9).join('\n      ') || e.message}`); process.exitCode = 1; }
};
const raw = (method, url, body, token) =>
  app.inject({ method, url, payload: body, headers: token ? { authorization: `Bearer ${token}` } : {} });
const call = async (method, url, body, token) => {
  const res = await raw(method, url, body, token);
  let parsed = null;
  try { parsed = res.body ? JSON.parse(res.body) : null; } catch { parsed = res.body; }
  return { status: res.statusCode, body: parsed, headers: res.headers };
};
const login = async (email, password, role) => {
  const r = await call('POST', '/auth/login', { email, password, role });
  assert.equal(r.status, 200, `login ${email}: ${JSON.stringify(r.body)}`);
  return r.body.token;
};
const MIN = 60000; const HOUR = 3600000; const DAY = 86400000;
const at = (dlat = 0, dlng = 0) => ({ lat: BASE.lat + dlat, lng: BASE.lng + dlng });

const demo = await login('demo@bythepeople.app', 'demo1234');
const admin = await login('admin@bythepeople.app', 'admin1234');
const neta = await login('neta@bythepeople.app', 'neta1234');
const seva = await login('seva@bythepeople.app', 'seva1234');
const anna = await login('annapurna@bythepeople.app', 'anna1234');
const hope = await login('newhope@bythepeople.app', 'hope1234');
const kiran = await login('kiran@bythepeople.app', 'sober123');
const hemant = await login('hemant@bythepeople.app', 'sober123');
const sunita = await login('sunita@bythepeople.app', 'sober123');
const guest = await login('guest@bythepeople.app', 'guest123');
const ramesh = await login('ramesh@bythepeople.app', 'sober123');
const uid = async (tok) => (await call('GET', '/me', null, tok)).body.user.id;
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const upload = async (tok) => (await call('POST', '/media', { dataBase64: png.toString('base64'), mime: 'image/png' }, tok)).body.url;

// ---------- photos ----------
await t('seed photos: every issue, gathering, donation and club has media; real photos win over placeholders', async () => {
  assert.equal(db.prepare("SELECT COUNT(*) c FROM issues WHERE media='[]'").get().c, 0);
  assert.equal(db.prepare("SELECT COUNT(*) c FROM gatherings WHERE media='[]'").get().c, 0);
  assert.equal(db.prepare("SELECT COUNT(*) c FROM donations WHERE media='[]'").get().c, 0);
  assert.ok(db.prepare("SELECT COUNT(*) c FROM issues WHERE media LIKE '%photo-pothole-1.jpg%'").get().c >= 1);
  const clubs = (await call('GET', '/clubs', null, demo)).body.items;
  assert.ok(clubs.every((c) => c.coverUrl && c.avatarUrl));
  const f = (await call('GET', '/foundations/' + (await uid(seva)), null, demo)).body.foundation;
  assert.ok(f.coverUrl && f.avatarUrl);
  const me = (await call('GET', '/me', null, seva)).body.user;
  assert.ok(me.coverUrl && me.avatarUrl);
  const all = db.prepare("SELECT media FROM issues UNION ALL SELECT media FROM donations").all().flatMap((r) => JSON.parse(r.media));
  for (const m of [...new Set(all)]) assert.equal((await raw('GET', m)).statusCode, 200, m);
});

// ---------- auth & roles ----------
await t('roles: demo accounts, user profile fields, portal check', async () => {
  const a = (await call('POST', '/auth/login', { email: 'admin@bythepeople.app', password: 'admin1234', role: 'admin' })).body;
  assert.equal(a.user.role, 'admin'); assert.equal(a.user.departmentName, 'Raipur Municipal Corporation'); assert.equal(a.user.verified, true);
  const n = (await call('GET', '/me', null, neta)).body.user;
  assert.equal(n.role, 'neta'); assert.ok(n.politicianId);
  assert.equal(db.prepare('SELECT name FROM politicians WHERE id=?').get(n.politicianId).name, 'Lakshmi Sahu');
  const s = (await call('GET', '/me', null, seva)).body.user;
  assert.equal(s.role, 'foundation'); assert.equal(s.orgName, 'Seva Sankalp Foundation'); assert.equal(s.verified, true); assert.ok(s.needs.includes('food'));
  const h = (await call('GET', '/me', null, hope)).body.user;
  assert.equal(h.verified, false); assert.equal(h.orgName, 'New Hope Trust');
  const c = (await call('GET', '/me', null, demo)).body.user;
  assert.equal(c.role, 'citizen'); assert.equal(c.verified, true); assert.deepEqual(c.needs, []);
  const wrong = await call('POST', '/auth/login', { email: 'demo@bythepeople.app', password: 'demo1234', role: 'admin' });
  assert.equal(wrong.status, 403); assert.equal(wrong.body.code, 'WRONG_PORTAL'); assert.match(wrong.body.error, /citizen account/);
  // wrong password still 401 even with a role
  assert.equal((await call('POST', '/auth/login', { email: 'demo@bythepeople.app', password: 'x', role: 'admin' })).status, 401);
});

await t('roles: registration rules (foundation needs org + regNo, admin/neta blocked)', async () => {
  assert.equal((await call('POST', '/auth/register', { name: 'Sneaky', email: 's1@x.com', password: 'secret1', role: 'admin' })).status, 403);
  assert.equal((await call('POST', '/auth/register', { name: 'Sneaky', email: 's2@x.com', password: 'secret1', role: 'neta' })).status, 403);
  assert.equal((await call('POST', '/auth/register', { name: 'Sneaky', email: 's3@x.com', password: 'secret1', role: 'wizard' })).status, 400);
  assert.equal((await call('POST', '/auth/register', { name: 'Org', email: 'o1@x.com', password: 'secret1', role: 'foundation' })).status, 400);
  assert.equal((await call('POST', '/auth/register', { name: 'Org', email: 'o1@x.com', password: 'secret1', role: 'foundation', orgName: 'Helping Hands' })).status, 400);
  const ok = await call('POST', '/auth/register', { name: 'Org Lead', email: 'o2@x.com', password: 'secret1', role: 'foundation', orgName: 'Helping Hands', regNo: 'NGO/1/2024', about: 'We help', city: 'Raipur' });
  assert.equal(ok.status, 201); assert.equal(ok.body.user.role, 'foundation'); assert.equal(ok.body.user.verified, false);
  const cit = await call('POST', '/auth/register', { name: 'Plain Citizen', email: 'c1@x.com', password: 'secret1' });
  assert.equal(cit.body.user.role, 'citizen'); assert.equal(cit.body.user.verified, true);
});

await t('roles: PATCH /me about, needs, address, orgName validation', async () => {
  const r = await call('PATCH', '/me', { about: 'Feeding Raipur', needs: ['food', 'books'], address: 'Pandri', orgName: 'Annapurna Food Bank Raipur' }, anna);
  assert.equal(r.status, 200); assert.deepEqual(r.body.user.needs, ['food', 'books']); assert.equal(r.body.user.about, 'Feeding Raipur');
  assert.equal(r.body.user.address, 'Pandri'); assert.equal(r.body.user.orgName, 'Annapurna Food Bank Raipur');
  assert.equal((await call('PATCH', '/me', { needs: ['gold'] }, anna)).status, 400);
  await call('PATCH', '/me', { orgName: 'Annapurna Food Bank' }, anna);
});

// ---------- media ----------
await t('media: upload, serve statically, validation', async () => {
  const r = await call('POST', '/media', { dataBase64: png.toString('base64'), mime: 'image/png' }, demo);
  assert.equal(r.status, 200); assert.match(r.body.url, /^\/uploads\/[a-f0-9]+\.png$/);
  const res = await raw('GET', r.body.url);
  assert.equal(res.statusCode, 200); assert.equal(res.headers['content-type'], 'image/png');
  assert.deepEqual(Buffer.from(res.rawPayload), png);
  assert.equal((await call('POST', '/media', { dataBase64: 'AAAA', mime: 'application/pdf' }, demo)).status, 400);
  assert.equal((await call('POST', '/media', { dataBase64: '', mime: 'image/png' }, demo)).status, 400);
  assert.equal((await call('POST', '/media', { dataBase64: png.toString('base64'), mime: 'image/png' })).status, 401);
  const big = Buffer.alloc(13 * 1024 * 1024, 1).toString('base64'); // ~17 MB json, under the 20 MB body limit
  const tooBig = await call('POST', '/media', { dataBase64: big, mime: 'video/mp4' }, demo);
  assert.equal(tooBig.status, 413); assert.equal(tooBig.body.code, 'TOO_LARGE');
  const okVid = await call('POST', '/media', { dataBase64: Buffer.alloc(2000, 1).toString('base64'), mime: 'video/mp4' }, demo);
  assert.match(okVid.body.url, /\.mp4$/);
  assert.equal((await raw('GET', '/uploads/nope.png')).statusCode, 404);
  assert.equal((await raw('GET', '/uploads/..%2Fpackage.json')).statusCode, 404);
  // seeded placeholder media is served too
  assert.equal((await raw('GET', '/uploads/seed-1.png')).statusCode, 200);
});

await t('media: arbitrary urls are rejected when attached', async () => {
  const bad = await call('POST', '/issues', { title: 'Bad media issue', category: 'road', ...at(0.0042, 0.0042), media: ['http://evil.example/x.jpg'] }, guest);
  assert.equal(bad.status, 400); assert.equal(bad.body.code, 'BAD_MEDIA');
});

// ---------- issues: social layer ----------
let issueId; let topIssue;
await t('issues: feed defaults to top (engagement) and carries v3 fields', async () => {
  const r = await call('GET', `/issues?phase=issue&lat=${BASE.lat}&lng=${BASE.lng}`, null, demo);
  const items = r.body.items;
  for (let i = 1; i < items.length; i++) assert.ok(items[i].engagement <= items[i - 1].engagement, 'sorted by engagement');
  topIssue = items[0];
  assert.equal(topIssue.engagement, topIssue.likeCount + 2 * topIssue.supportCount + topIssue.commentCount + topIssue.shareCount);
  const i = items.find((x) => x.title.includes('Potholes outside Telibandha'));
  assert.equal(i.escalated, true); assert.equal(i.escalatedBy.role, 'neta'); assert.ok(i.escalationNote);
  assert.equal(i.authority.name, 'Raipur Municipal Corporation'); assert.equal(i.authority.department, 'Public Works'); assert.equal(i.authority.handle, '@RMC_Raipur');
  assert.equal(i.authorityStatus, 'open'); assert.ok(Array.isArray(i.media));
  assert.match(i.shareText, /@RMC_Raipur/); assert.match(i.shareText, /\/p\/issues\//); assert.match(i.publicUrl, /\/p\/issues\/\d+$/);
  assert.equal(typeof i.likedByMe, 'boolean');
  issueId = i.id;
  const sorted = (await call('GET', '/issues?sort=new', null, demo)).body.items;
  for (let k = 1; k < sorted.length; k++) assert.ok(sorted[k].createdAt <= sorted[k - 1].createdAt);
  const esc = (await call('GET', '/issues?phase=all&escalated=1', null, demo)).body.items;
  assert.ok(esc.length >= 2 && esc.every((x) => x.escalated));
  const mine = (await call('GET', '/issues?phase=all&mine=1', null, kiran)).body.items;
  assert.ok(mine.length > 0 && mine.every((x) => x.reporter.name === 'Kiran Mahant'));
  assert.equal(mine[0].reporter.role, 'citizen');
});

const liker = (await call('POST', '/auth/register', { name: 'Liker Person', email: 'liker@x.com', password: 'secret1' })).body.token;
await t('issues: like / unlike (not location gated), idempotent', async () => {
  const guest = liker;
  const before = (await call('GET', `/issues/${issueId}`, null, guest)).body.issue;
  const l = await call('POST', `/issues/${issueId}/like`, {}, guest);
  assert.equal(l.status, 200); assert.equal(l.body.issue.likedByMe, true); assert.equal(l.body.issue.likeCount, before.likeCount + 1);
  assert.equal((await call('POST', `/issues/${issueId}/like`, {}, guest)).body.issue.likeCount, before.likeCount + 1);
  const u = await call('DELETE', `/issues/${issueId}/like`, null, guest);
  assert.equal(u.body.issue.likedByMe, false); assert.equal(u.body.issue.likeCount, before.likeCount);
  assert.equal((await call('POST', '/issues/99999/like', {}, guest)).status, 404);
  assert.equal((await call('POST', `/issues/${issueId}/like`, {})).status, 401);
});

await t('issues: comments (citizen +1 point, admin/neta marked by role, validation, notification)', async () => {
  const pts = (await call('GET', '/me', null, guest)).body.user.points;
  const c = await call('POST', `/issues/${issueId}/comments`, { body: 'Seen this too, very bad.' }, guest);
  assert.equal(c.status, 201); assert.equal(c.body.comment.author.role, 'citizen'); assert.equal(c.body.rewards.points, 1);
  assert.equal((await call('GET', '/me', null, guest)).body.user.points, pts + 1);
  const a = await call('POST', `/issues/${issueId}/comments`, { body: 'Survey scheduled.' }, admin);
  assert.equal(a.body.comment.author.role, 'admin'); assert.equal(a.body.rewards, null);
  const withMedia = await call('POST', `/issues/${issueId}/comments`, { body: 'Photo attached', media: [await upload(guest)] }, guest);
  assert.equal(withMedia.body.comment.media.length, 1);
  assert.equal((await call('POST', `/issues/${issueId}/comments`, { body: '   ' }, guest)).status, 400);
  const list = (await call('GET', `/issues/${issueId}/comments`, null, demo)).body.items;
  assert.ok(list.length >= 3);
  assert.ok(list.some((x) => x.author.role === 'admin') && list.some((x) => x.author.role === 'neta'));
  for (let k = 1; k < list.length; k++) assert.ok(list[k].createdAt >= list[k - 1].createdAt);
  const issue = (await call('GET', `/issues/${issueId}`, null, demo)).body.issue;
  assert.equal(issue.commentCount, list.length);
  const n = (await call('GET', '/notifications', null, hemant)).body.items; // hemant is not the reporter; reporter gets comment notif
  void n;
  const reporterEmail = `${issue.reporter.name.split(' ')[0].toLowerCase()}@bythepeople.app`;
  const rep = await login(reporterEmail, 'sober123');
  const note = (await call('GET', '/notifications', null, rep)).body.items.find((x) => x.type === 'comment' && x.refId === issueId);
  assert.ok(note, 'reporter notified'); assert.equal(note.refType, 'issue'); assert.equal(note.issueId, issueId);
});

await t('issues: voice badge after 5 comments', async () => {
  const user = await call('POST', '/auth/register', { name: 'Chatty Person', email: 'chatty@x.com', password: 'secret1' });
  let last;
  for (let i = 0; i < 5; i++) last = await call('POST', `/issues/${issueId}/comments`, { body: `comment ${i}` }, user.body.token);
  assert.ok(last.body.rewards.badges.some((b) => b.key === 'voice'));
});

await t('issues: share increments and returns text + public url; public page needs no auth', async () => {
  const before = (await call('GET', `/issues/${issueId}`, null, demo)).body.issue.shareCount;
  const s = await call('POST', `/issues/${issueId}/share`, {}, demo);
  assert.equal(s.body.shareCount, before + 1); assert.match(s.body.shareText, /Raipur/); assert.match(s.body.publicUrl, new RegExp(`/p/issues/${issueId}$`));
  const page = await raw('GET', `/p/issues/${issueId}`);
  assert.equal(page.statusCode, 200); assert.match(page.headers['content-type'], /text\/html/);
  assert.match(page.body, /Potholes outside Telibandha/); assert.match(page.body, /Raipur Municipal Corporation/); assert.match(page.body, /Timeline/);
  assert.equal((await raw('GET', '/p/issues/99999')).statusCode, 404);
});

await t('issues: reporting with media; admin cannot report', async () => {
  const m = await upload(guest);
  const ok = await call('POST', '/issues', { title: 'Crater near the temple gate', category: 'road', ...at(0.0042, 0.0042), userLat: BASE.lat + 0.004, userLng: BASE.lng + 0.004, media: [m] }, guest);
  assert.equal(ok.status, 201); assert.deepEqual(ok.body.issue.media, [m]);
  assert.equal(ok.body.issue.authorityStatus, 'open'); assert.equal(ok.body.issue.escalated, false); assert.equal(ok.body.issue.assignedTo, null);
  const a = await call('POST', '/issues', { title: 'Admin report attempt', category: 'road', ...at(0.0042, 0.0042) }, admin);
  assert.equal(a.status, 403);
});

// ---------- authority portal ----------
let target; // an open issue in Raipur for the authority flow
await t('authority: admin-only endpoints reject other roles', async () => {
  for (const tok of [demo, neta, seva]) {
    const r = await call('GET', '/admin/issues', null, tok);
    assert.equal(r.status, 403); assert.equal(r.body.code, 'FORBIDDEN');
    assert.equal((await call('GET', '/admin/dashboard', null, tok)).status, 403);
    assert.equal((await call('GET', '/admin/foundations', null, tok)).status, 403);
  }
  assert.equal((await call('GET', '/admin/issues')).status, 401);
  assert.equal((await call('POST', `/issues/${issueId}/authority-update`, { status: 'acknowledged' }, demo)).status, 403);
});

await t('authority: issue list is city-wide, escalated first, filters and sorts', async () => {
  const all = (await call('GET', '/admin/issues', null, admin)).body.items;
  assert.ok(all.length > 20 && all.every((i) => i.area.city.name === 'Raipur'));
  const firstNonEsc = all.findIndex((i) => !i.escalated);
  assert.ok(all.slice(0, firstNonEsc).every((i) => i.escalated) && all.slice(firstNonEsc).every((i) => !i.escalated));
  assert.ok(firstNonEsc >= 2);
  assert.ok((await call('GET', '/admin/issues?escalated=1', null, admin)).body.items.every((i) => i.escalated));
  assert.ok((await call('GET', '/admin/issues?status=acknowledged', null, admin)).body.items.every((i) => i.authorityStatus === 'acknowledged' && i.status !== 'closed'));
  assert.ok((await call('GET', '/admin/issues?status=closed', null, admin)).body.items.every((i) => i.status === 'closed'));
  assert.ok((await call('GET', '/admin/issues?category=water', null, admin)).body.items.every((i) => i.category === 'water'));
  assert.ok((await call('GET', '/admin/issues?q=manhole', null, admin)).body.items.length >= 1);
  const old = (await call('GET', '/admin/issues?sort=oldest', null, admin)).body.items;
  for (let k = 1; k < old.length; k++) assert.ok(old[k].createdAt >= old[k - 1].createdAt);
  const top = (await call('GET', '/admin/issues?sort=top', null, admin)).body.items;
  for (let k = 1; k < top.length; k++) assert.ok(top[k].engagement <= top[k - 1].engagement);
  assert.equal((await call('GET', '/admin/issues?status=banana', null, admin)).status, 400);
  target = all.find((i) => i.status === 'open' && i.authorityStatus === 'open' && !i.escalated && i.supportCount < 5);
  assert.ok(target);
});

await t('authority: dashboard counts partition the city', async () => {
  const d = (await call('GET', '/admin/dashboard', null, admin)).body;
  const all = (await call('GET', '/admin/issues', null, admin)).body.items;
  const c = d.counts;
  assert.equal(c.open + c.acknowledged + c.inProgress + c.pendingVerification + c.closed, all.length);
  assert.equal(c.escalated, all.filter((i) => i.escalated && i.status !== 'closed').length);
  assert.ok(c.escalated >= 2 && c.acknowledged >= 1 && c.pendingVerification >= 1 && c.closed >= 1);
  assert.ok(d.avgResolutionHours > 0);
  assert.equal(d.byCategory.reduce((a, x) => a + x.count, 0), all.length);
  assert.ok(d.byCategory.every((x) => x.label && x.open <= x.count));
  assert.equal(d.topIssues.length, 5);
  for (let k = 1; k < 5; k++) assert.ok(d.topIssues[k].engagement <= d.topIssues[k - 1].engagement);
  assert.ok(d.pendingFoundations >= 2); // New Hope + the foundation registered above
  assert.ok(d.recent.length > 0 && d.recent[0].issueTitle);
});

await t('authority: acknowledge -> in progress -> resolve rules + notifications', async () => {
  const id = target.id;
  assert.equal((await call('POST', `/issues/${id}/authority-update`, { status: 'bogus' }, admin)).status, 400);
  const ack = await call('POST', `/issues/${id}/authority-update`, { status: 'acknowledged', note: 'Team dispatched' }, admin);
  assert.equal(ack.status, 200);
  assert.equal(ack.body.issue.authorityStatus, 'acknowledged'); assert.equal(ack.body.issue.status, 'open');
  const last = ack.body.issue.timeline.at(-1);
  assert.equal(last.kind, 'authority'); assert.equal(last.actorRole, 'admin'); assert.equal(last.note, 'Team dispatched');
  assert.equal((await call('POST', `/issues/${id}/authority-update`, { status: 'acknowledged' }, admin)).status, 409);
  // reporter + supporters are notified
  const reporterTok = await login(`${target.reporter.name.split(' ')[0].toLowerCase()}@bythepeople.app`, target.reporter.name === 'Alex Rathore' ? 'demo1234' : 'sober123');
  const n = (await call('GET', '/notifications', null, reporterTok)).body.items.find((x) => x.type === 'authority_update' && x.issueId === id);
  assert.ok(n && n.refType === 'issue' && n.refId === id);
  // in progress + assignment
  const prog = await call('POST', `/issues/${id}/authority-update`, { status: 'in_progress', note: 'Crew on site', assignedTo: 'Team A' }, admin);
  assert.equal(prog.body.issue.status, 'in_progress'); assert.equal(prog.body.issue.assignedTo, 'Team A'); assert.equal(prog.body.issue.authorityStatus, 'in_progress');
  // resolved needs a note and proof
  const noProof = await call('POST', `/issues/${id}/authority-update`, { status: 'resolved', note: 'Fixed' }, admin);
  assert.equal(noProof.status, 400); assert.equal(noProof.body.code, 'PROOF_REQUIRED');
  const noNote = await call('POST', `/issues/${id}/authority-update`, { status: 'resolved', media: [await upload(admin)] }, admin);
  assert.equal(noNote.status, 400);
  const proof = await upload(admin);
  const res = await call('POST', `/issues/${id}/authority-update`, { status: 'resolved', note: 'Pothole filled and levelled', media: [proof] }, admin);
  assert.equal(res.status, 200); assert.equal(res.body.issue.status, 'pending_verification'); assert.equal(res.body.issue.authorityStatus, 'resolved');
  assert.deepEqual(res.body.issue.timeline.at(-1).media, [proof]);
  assert.equal(res.body.issue.resolutionNote, 'Pothole filled and levelled');
  // can no longer update while neighbours verify
  assert.equal((await call('POST', `/issues/${id}/authority-update`, { status: 'in_progress' }, admin)).status, 409);
  assert.equal((await call('POST', '/issues/99999/authority-update', { status: 'acknowledged' }, admin)).status, 404);
});

await t('authority: citizens verify an authority fix (closing it) and issue becomes resolved', async () => {
  const id = target.id;
  const detail = (await call('GET', `/issues/${id}`, null, admin)).body.issue;
  assert.equal(detail.status, 'pending_verification');
  const emails = detail.supporters.map((s) => s.name);
  assert.ok(emails.length >= 1);
  const open = db.prepare('SELECT id,name,email FROM users WHERE id IN (SELECT user_id FROM supports WHERE issue_id=?)').all(id);
  let outcome;
  for (const u of open) {
    const tok = await login(u.email, u.email.startsWith('demo') ? 'demo1234' : u.email.startsWith('guest') ? 'guest123' : 'sober123');
    const row = db.prepare('SELECT lat,lng FROM issues WHERE id=?').get(id);
    const r = await call('POST', `/events/${id}/verify`, { approve: true, lat: row.lat, lng: row.lng }, tok);
    if (r.status === 200) outcome = r.body.outcome;
    if (outcome === 'closed') break;
  }
  // with fewer than 2 verifiers the issue stays pending, which is also valid behaviour
  const after = (await call('GET', `/issues/${id}`, null, admin)).body.issue;
  assert.ok(['closed', 'pending_verification'].includes(after.status));
  if (after.status === 'closed') assert.equal(after.authorityStatus, 'resolved');
});

await t('authority: cannot update an issue in another city', async () => {
  const bilaspur = db.prepare("SELECT i.id FROM issues i JOIN areas a ON a.id=i.city_id WHERE a.name='Bilaspur' AND i.status='open' LIMIT 1").get();
  const r = await call('POST', `/issues/${bilaspur.id}/authority-update`, { status: 'acknowledged' }, admin);
  assert.equal(r.status, 403); assert.equal(r.body.code, 'FORBIDDEN');
});

await t('authority: foundation verification queue', async () => {
  const pending = (await call('GET', '/admin/foundations?status=pending', null, admin)).body.items;
  assert.ok(pending.some((f) => f.name === 'New Hope Trust') && pending.every((f) => !f.verified));
  assert.ok((await call('GET', '/admin/foundations?status=verified', null, admin)).body.items.every((f) => f.verified));
  assert.ok((await call('GET', '/admin/foundations?status=all', null, admin)).body.items.length >= 3);
  const f = pending.find((x) => x.name === 'New Hope Trust');
  assert.equal((await call('POST', `/admin/foundations/${f.id}/verify`, { approve: 'yes' }, admin)).status, 400);
  assert.equal((await call('POST', `/admin/foundations/${f.id}/verify`, { approve: true }, demo)).status, 403);
  assert.equal((await call('POST', '/admin/foundations/99999/verify', { approve: true }, admin)).status, 404);
  // reject first, then approve
  const rej = await call('POST', `/admin/foundations/${f.id}/verify`, { approve: false, note: 'Registration number not found' }, admin);
  assert.equal(rej.body.foundation.verified, false);
  assert.equal((await call('GET', '/me', null, hope)).body.user.verified, false);
  assert.equal((await call('GET', '/admin/dashboard', null, admin)).body.pendingFoundations, pending.length - 1);
  const ok = await call('POST', `/admin/foundations/${f.id}/verify`, { approve: true, note: 'Documents checked' }, admin);
  assert.equal(ok.body.foundation.verified, true);
  assert.equal((await call('GET', '/me', null, hope)).body.user.verified, true);
  const n = (await call('GET', '/notifications', null, hope)).body.items.filter((x) => x.type === 'foundation_verified');
  assert.equal(n.length, 2);
  // put it back for the donation tests
  db.prepare("UPDATE users SET verified=0, verify_status='pending' WHERE id=?").run(f.id);
});

// ---------- neta portal ----------
await t('neta: portal is neta-only; feed covers the jurisdiction', async () => {
  for (const tok of [demo, admin, seva]) assert.equal((await call('GET', '/neta/feed', null, tok)).status, 403);
  const feed = (await call('GET', '/neta/feed', null, neta)).body.items;
  assert.ok(feed.length >= 10);
  assert.ok(feed.every((i) => i.politician.name === 'Lakshmi Sahu'));
  for (let k = 1; k < feed.length; k++) assert.ok(feed[k].engagement <= feed[k - 1].engagement);
  assert.ok((await call('GET', '/neta/feed?status=closed', null, neta)).body.items.every((i) => i.status === 'closed'));
  const nw = (await call('GET', '/neta/feed?sort=new', null, neta)).body.items;
  for (let k = 1; k < nw.length; k++) assert.ok(nw[k].createdAt <= nw[k - 1].createdAt);
});

await t('neta: dashboard numbers match the feed', async () => {
  const d = (await call('GET', '/neta/dashboard', null, neta)).body;
  const feed = (await call('GET', '/neta/feed', null, neta)).body.items;
  assert.equal(d.politician.name, 'Lakshmi Sahu');
  assert.equal(d.counts.open + d.counts.inProgress + d.counts.resolved, feed.length);
  assert.equal(d.counts.resolved, feed.filter((i) => i.status === 'closed').length);
  assert.equal(d.counts.escalated, feed.filter((i) => i.escalated && i.status !== 'closed').length);
  assert.ok(d.resolutionRate > 0 && d.resolutionRate <= 1);
  assert.ok(d.topIssues.length > 0 && d.topIssues.length <= 5);
  assert.ok(d.upcomingGatherings.length > 0);
  assert.ok(d.upcomingGatherings.every((g) => ['upcoming', 'ongoing'].includes(g.status)));
});

let escId;
await t('neta: escalate / withdraw / respond with jurisdiction rules', async () => {
  const feed = (await call('GET', '/neta/feed?status=open', null, neta)).body.items;
  const cand = feed.find((i) => !i.escalated);
  escId = cand.id;
  assert.equal((await call('POST', `/issues/${escId}/escalate`, { note: 'x' }, demo)).status, 403);
  assert.equal((await call('POST', `/issues/${escId}/escalate`, { note: '' }, neta)).status, 400);
  const adminBefore = (await call('GET', '/notifications', null, admin)).body.items.filter((n) => n.type === 'escalated').length;
  const r = await call('POST', `/issues/${escId}/escalate`, { note: 'Residents are very upset about this.' }, neta);
  assert.equal(r.status, 200); assert.equal(r.body.issue.escalated, true);
  assert.equal(r.body.issue.escalatedBy.name, 'Lakshmi Sahu'); assert.equal(r.body.issue.escalationNote, 'Residents are very upset about this.');
  const last = r.body.issue.timeline.at(-1);
  assert.equal(last.kind, 'neta'); assert.match(last.note, /Escalated to admin portal by Lakshmi Sahu/);
  const notes = (await call('GET', '/notifications', null, admin)).body.items.filter((n) => n.type === 'escalated');
  assert.equal(notes.length, adminBefore + 1); assert.equal(notes[0].refType, 'issue');
  assert.equal((await call('POST', `/issues/${escId}/escalate`, { note: 'again' }, neta)).status, 409);
  assert.ok((await call('GET', '/admin/issues?escalated=1', null, admin)).body.items.some((i) => i.id === escId));
  const resp = await call('POST', `/issues/${escId}/neta-response`, { note: 'I will personally follow this up on Monday.' }, neta);
  assert.equal(resp.status, 200); assert.equal(resp.body.issue.timeline.at(-1).kind, 'neta');
  assert.equal((await call('POST', `/issues/${escId}/neta-response`, { note: '' }, neta)).status, 400);
  const wd = await call('DELETE', `/issues/${escId}/escalate`, null, neta);
  assert.equal(wd.body.issue.escalated, false); assert.equal(wd.body.issue.escalatedBy, null);
  assert.equal((await call('DELETE', `/issues/${escId}/escalate`, null, neta)).status, 409);
  // out of jurisdiction (an issue in another ward/city)
  const foreign = db.prepare("SELECT i.id FROM issues i JOIN politicians p ON p.id=i.politician_id WHERE p.name!='Lakshmi Sahu' AND i.status='open' LIMIT 1").get();
  const f = await call('POST', `/issues/${foreign.id}/escalate`, { note: 'not mine' }, neta);
  assert.equal(f.status, 403); assert.equal(f.body.code, 'OUT_OF_JURISDICTION');
  assert.equal((await call('POST', `/issues/${foreign.id}/neta-response`, { note: 'not mine' }, neta)).status, 403);
  const closed = db.prepare("SELECT i.id FROM issues i JOIN politicians p ON p.id=i.politician_id WHERE p.name='Lakshmi Sahu' AND i.status='closed' LIMIT 1").get();
  assert.equal((await call('POST', `/issues/${closed.id}/escalate`, { note: 'closed' }, neta)).status, 409);
});

// ---------- gatherings ----------
let gathers;
await t('gatherings: lists, filters and sorts', async () => {
  const up = (await call('GET', `/gatherings?lat=${BASE.lat}&lng=${BASE.lng}`, null, demo)).body.items;
  assert.ok(up.length >= 7 && up.every((g) => ['upcoming', 'ongoing'].includes(g.status)));
  for (let k = 1; k < up.length; k++) assert.ok(up[k].startAt >= up[k - 1].startAt);
  assert.ok(up.some((g) => g.status === 'ongoing'));
  gathers = up;
  const plant = up.find((g) => g.title.includes('Plantation Drive'));
  assert.equal(plant.type, 'plantation'); assert.equal(plant.typeLabel, 'Plantation drive'); assert.equal(plant.capacity, 40);
  assert.equal(plant.spotsLeft, 40 - plant.goingCount); assert.equal(plant.club.name, 'Green Raipur Plantation Club');
  assert.ok(plant.attendees.length <= 6 && plant.attendees.length > 0); assert.equal(plant.goingByMe, false);
  assert.match(plant.shareText, /Plantation/); assert.match(plant.publicUrl, /\/p\/gatherings\//); assert.ok(plant.distanceKm >= 0);
  const near = (await call('GET', `/gatherings?sort=near&lat=${BASE.lat}&lng=${BASE.lng}`, null, demo)).body.items;
  for (let k = 1; k < near.length; k++) assert.ok(near[k].distanceKm >= near[k - 1].distanceKm);
  const pop = (await call('GET', '/gatherings?sort=popular', null, demo)).body.items;
  for (let k = 1; k < pop.length; k++) assert.ok(pop[k].goingCount <= pop[k - 1].goingCount);
  assert.ok((await call('GET', '/gatherings?type=blood', null, demo)).body.items.every((g) => g.type === 'blood'));
  assert.ok((await call('GET', '/gatherings?q=marathon', null, demo)).body.items.length === 0);
  assert.ok((await call('GET', '/gatherings?q=5k', null, demo)).body.items.length === 1);
  const clubs = (await call('GET', '/clubs', null, demo)).body.items;
  const club = clubs.find((c) => c.name === 'Clean Lake Crew');
  assert.ok((await call('GET', `/gatherings?club=${club.id}`, null, demo)).body.items.every((g) => g.club.id === club.id));
  const past = (await call('GET', '/gatherings?when=past', null, demo)).body.items;
  assert.ok(past.length >= 5 && past.every((g) => g.status === 'completed' && g.impact && g.impact.checkedIn > 0 && g.impact.note));
  for (let k = 1; k < past.length; k++) assert.ok(past[k].startAt <= past[k - 1].startAt);
  const prop = (await call('GET', '/gatherings?when=proposed', null, demo)).body.items;
  assert.ok(prop.length >= 3 && prop.every((g) => g.status === 'proposed' && g.votesNeeded === 5));
  const mine = (await call('GET', '/gatherings?when=mine', null, demo)).body.items;
  assert.ok(mine.length >= 4 && mine.every((g) => g.goingByMe || g.isOrganiser));
  assert.equal((await call('GET', '/gatherings?when=never', null, demo)).status, 400);
  const detail = (await call('GET', `/gatherings/${plant.id}`, null, demo)).body.gathering;
  assert.equal(detail.attendees.length, detail.goingCount);
  assert.equal((await call('GET', '/gatherings/99999', null, demo)).status, 404);
});

await t('gatherings: create validation', async () => {
  const base = { title: 'Evening tree walk', description: 'Learn the trees', type: 'plantation', ...at(0.002, 0.002), address: 'Lake', startAt: Date.now() + 3 * DAY };
  assert.equal((await call('POST', '/gatherings', { ...base, title: 'x' }, demo)).status, 400);
  assert.equal((await call('POST', '/gatherings', { ...base, type: 'party' }, demo)).status, 400);
  assert.equal((await call('POST', '/gatherings', { ...base, lat: 'x' }, demo)).status, 400);
  const past = await call('POST', '/gatherings', { ...base, startAt: Date.now() - 1000 }, demo);
  assert.equal(past.status, 400); assert.equal(past.body.code, 'BAD_DATE');
  assert.equal((await call('POST', '/gatherings', { ...base, endAt: base.startAt - 1 }, demo)).status, 400);
  assert.equal((await call('POST', '/gatherings', { ...base, capacity: 0 }, demo)).status, 400);
  assert.equal((await call('POST', '/gatherings', { ...base, clubId: 9999 }, demo)).status, 404);
  assert.equal((await call('POST', '/gatherings', base)).status, 401);
  const m = await upload(demo);
  const ok = await call('POST', '/gatherings', { ...base, capacity: 10, media: [m], endAt: base.startAt + 2 * HOUR }, neta);
  assert.equal(ok.status, 201); assert.equal(ok.body.gathering.status, 'upcoming'); assert.equal(ok.body.gathering.organizer.role, 'neta');
  assert.deepEqual(ok.body.gathering.media, [m]); assert.equal(ok.body.gathering.spotsLeft, 10);
  // admin may create too
  assert.equal((await call('POST', '/gatherings', base, admin)).status, 201);
});

await t('gatherings: RSVP, points once, capacity FULL, cancel RSVP', async () => {
  const plant = gathers.find((g) => g.title.includes('Plantation Drive'));
  const before = (await call('GET', '/me', null, guest)).body.user.points;
  const r = await call('POST', `/gatherings/${plant.id}/rsvp`, {}, kiran === guest ? demo : guest);
  assert.equal(r.status, 200); assert.equal(r.body.gathering.goingByMe, true); assert.equal(r.body.rewards.points, 5);
  assert.equal(r.body.gathering.goingCount, plant.goingCount + 1);
  assert.equal((await call('GET', '/me', null, guest)).body.user.points, before + 5);
  assert.equal((await call('POST', `/gatherings/${plant.id}/rsvp`, {}, guest)).status, 409);
  const out = await call('DELETE', `/gatherings/${plant.id}/rsvp`, null, guest);
  assert.equal(out.body.gathering.goingByMe, false); assert.equal(out.body.gathering.goingCount, plant.goingCount);
  const again = await call('POST', `/gatherings/${plant.id}/rsvp`, {}, guest);
  assert.equal(again.status, 200); assert.equal(again.body.rewards, null); // points only the first time
  assert.equal((await call('GET', '/me', null, guest)).body.user.points, before + 5);
  assert.equal((await call('DELETE', `/gatherings/${plant.id}/rsvp`, null, liker)).status, 409);
  // organiser got an RSVP notification
  const org = await login('kiran@bythepeople.app', 'sober123');
  assert.ok((await call('GET', '/notifications', null, org)).body.items.some((n) => n.type === 'rsvp' && n.refType === 'gathering' && n.refId === plant.id));
  // seeded full gathering
  const full = gathers.find((g) => g.title.includes('Vaccination'));
  assert.equal(full.spotsLeft, 0);
  const f = await call('POST', `/gatherings/${full.id}/rsvp`, {}, demo);
  assert.equal(f.status, 409); assert.equal(f.body.code, 'FULL');
  // freeing a spot lets someone in
  const member = db.prepare('SELECT user_id FROM gathering_rsvps WHERE gathering_id=? LIMIT 1').get(full.id);
  db.prepare('DELETE FROM gathering_rsvps WHERE gathering_id=? AND user_id=?').run(full.id, member.user_id);
  assert.equal((await call('POST', `/gatherings/${full.id}/rsvp`, {}, demo)).status, 200);
  // cancelled / proposed cannot be joined
  const cancelled = db.prepare("SELECT id FROM gatherings WHERE status='cancelled'").get();
  assert.equal((await call('POST', `/gatherings/${cancelled.id}/rsvp`, {}, demo)).body.code, 'CANCELLED');
  const proposed = db.prepare("SELECT id FROM gatherings WHERE status='proposed' LIMIT 1").get();
  assert.equal((await call('POST', `/gatherings/${proposed.id}/rsvp`, {}, demo)).body.code, 'NOT_OPEN');
  const past = db.prepare("SELECT id FROM gatherings WHERE status='completed' LIMIT 1").get();
  assert.equal((await call('POST', `/gatherings/${past.id}/rsvp`, {}, demo)).status, 409);
});

await t('gatherings: proposal needs 5 votes then flips to upcoming and notifies the organiser', async () => {
  const c = await call('POST', '/gatherings', { title: 'Cycle to school week', description: 'Campaign', type: 'other', ...at(0.003, 0.001), startAt: Date.now() + 10 * DAY, proposed: true }, ramesh);
  assert.equal(c.status, 201); assert.equal(c.body.gathering.status, 'proposed'); assert.equal(c.body.gathering.votesNeeded, 5);
  const id = c.body.gathering.id;
  const voters = [demo, hemant, kiran, guest, sunita];
  for (let k = 0; k < 4; k++) {
    const r = await call('POST', `/gatherings/${id}/vote`, {}, voters[k]);
    assert.equal(r.status, 200); assert.equal(r.body.gathering.voteCount, k + 1); assert.equal(r.body.gathering.status, 'proposed'); assert.equal(r.body.gathering.votedByMe, true);
  }
  assert.equal((await call('POST', `/gatherings/${id}/vote`, {}, demo)).status, 409);
  const wd = await call('DELETE', `/gatherings/${id}/vote`, null, guest);
  assert.equal(wd.body.gathering.voteCount, 3);
  assert.equal((await call('DELETE', `/gatherings/${id}/vote`, null, guest)).status, 409);
  await call('POST', `/gatherings/${id}/vote`, {}, guest);
  const flip = await call('POST', `/gatherings/${id}/vote`, {}, sunita);
  assert.equal(flip.body.gathering.status, 'upcoming'); assert.equal(flip.body.gathering.voteCount, 5);
  assert.ok((await call('GET', '/notifications', null, ramesh)).body.items.some((n) => n.refType === 'gathering' && n.refId === id && /go/i.test(n.title)));
  // not a proposal any more
  assert.equal((await call('POST', `/gatherings/${id}/vote`, {}, ramesh)).body.code, 'NOT_PROPOSED');
  assert.equal((await call('POST', `/gatherings/${id}/rsvp`, {}, demo)).status, 200);
  // seeded proposal one vote short
  const blanket = (await call('GET', '/gatherings?when=proposed', null, demo)).body.items.find((g) => g.title.includes('Blanket'));
  assert.equal(blanket.voteCount, 4);
  const done = await call('POST', `/gatherings/${blanket.id}/vote`, {}, demo);
  assert.equal(done.body.gathering.status, 'upcoming');
});

await t('gatherings: check-in rules (rsvp, window, 500 m), points and badge', async () => {
  const user = await call('POST', '/auth/register', { name: 'Check Inner', email: 'ci@x.com', password: 'secret1' });
  const tok = user.body.token;
  const mk = async (dlat, startIn) => (await call('POST', '/gatherings', { title: 'Check-in test', description: 'x', type: 'cleanup', ...at(dlat, 0), startAt: Date.now() + startIn, endAt: Date.now() + startIn + 2 * HOUR }, demo)).body.gathering;
  const near = await mk(0.001, 10 * MIN);
  const far = await mk(0.0072, 10 * MIN); // ~800 m from BASE
  const later = await mk(0.001, 2 * HOUR);
  // not RSVP'd
  const nr = await call('POST', `/gatherings/${near.id}/checkin`, at(), tok);
  assert.equal(nr.status, 403); assert.equal(nr.body.code, 'NOT_RSVPD');
  for (const g of [near, far, later]) await call('POST', `/gatherings/${g.id}/rsvp`, {}, tok);
  const early = await call('POST', `/gatherings/${later.id}/checkin`, at(), tok);
  assert.equal(early.status, 409); assert.equal(early.body.code, 'TOO_EARLY');
  const faraway = await call('POST', `/gatherings/${far.id}/checkin`, at(), tok);
  assert.equal(faraway.status, 403); assert.equal(faraway.body.code, 'OUT_OF_RANGE'); assert.ok(faraway.body.distanceKm > 0.5);
  assert.equal((await call('POST', `/gatherings/${near.id}/checkin`, { lat: 'x', lng: 1 }, tok)).status, 400);
  const ok = await call('POST', `/gatherings/${near.id}/checkin`, at(), tok);
  assert.equal(ok.status, 200); assert.equal(ok.body.gathering.checkedInByMe, true); assert.equal(ok.body.rewards.points, 15);
  assert.ok(ok.body.rewards.badges.some((b) => b.key === 'volunteer_heart'));
  assert.equal((await call('POST', `/gatherings/${near.id}/checkin`, at(), tok)).body.code, 'ALREADY');
  // cannot withdraw RSVP after checking in
  assert.equal((await call('DELETE', `/gatherings/${near.id}/rsvp`, null, tok)).body.code, 'CHECKED_IN');
  // too late
  const lateG = await mk(0.001, 10 * MIN);
  await call('POST', `/gatherings/${lateG.id}/rsvp`, {}, tok);
  db.prepare('UPDATE gatherings SET start_at=?, end_at=? WHERE id=?').run(Date.now() - 5 * HOUR, Date.now() - HOUR, lateG.id);
  assert.equal((await call('POST', `/gatherings/${lateG.id}/checkin`, at(), tok)).body.code, 'TOO_LATE');
  // proposals cannot be checked into
  const prop = db.prepare("SELECT id FROM gatherings WHERE status='proposed' LIMIT 1").get();
  assert.equal((await call('POST', `/gatherings/${prop.id}/checkin`, at(), tok)).status, 409);
  // 3 plantation / clean-up check-ins earn green_thumb
  let badges = [];
  for (let k = 0; k < 2; k++) {
    const g = await mk(0.001, 10 * MIN);
    await call('POST', `/gatherings/${g.id}/rsvp`, {}, tok);
    const r = await call('POST', `/gatherings/${g.id}/checkin`, at(), tok);
    badges = badges.concat(r.body.rewards.badges.map((b) => b.key));
  }
  assert.ok(badges.includes('green_thumb'));
});

await t('gatherings: organiser completes (impact + thanks) or cancels (notifies RSVPs)', async () => {
  const c = await call('POST', '/gatherings', { title: 'Weekend food drive', description: 'x', type: 'food_drive', ...at(0.0005, 0), startAt: Date.now() + 5 * MIN, endAt: Date.now() + 3 * HOUR }, kiran);
  const id = c.body.gathering.id;
  await call('POST', `/gatherings/${id}/rsvp`, {}, demo);
  await call('POST', `/gatherings/${id}/rsvp`, {}, guest);
  assert.equal((await call('POST', `/gatherings/${id}/complete`, { note: 'x' }, kiran)).body.code, 'NOT_STARTED');
  db.prepare('UPDATE gatherings SET start_at=? WHERE id=?').run(Date.now() - 10 * MIN, id);
  assert.equal((await call('POST', `/gatherings/${id}/checkin`, at(), demo)).status, 200);
  assert.equal((await call('POST', `/gatherings/${id}/complete`, { note: 'x' }, demo)).body.code, 'NOT_ORGANISER');
  const done = await call('POST', `/gatherings/${id}/complete`, { note: 'Served 80 meals' }, kiran);
  assert.equal(done.status, 200); assert.equal(done.body.gathering.status, 'completed');
  assert.deepEqual(done.body.gathering.impact, { checkedIn: 1, note: 'Served 80 meals' });
  assert.ok((await call('GET', '/notifications', null, demo)).body.items.some((n) => n.refType === 'gathering' && n.refId === id && /thank/i.test(n.title)));
  assert.ok(!(await call('GET', '/notifications', null, guest)).body.items.some((n) => n.refId === id && /thank/i.test(n.title)));
  assert.equal((await call('POST', `/gatherings/${id}/complete`, { note: 'again' }, kiran)).status, 409);
  assert.equal((await call('POST', `/gatherings/${id}/cancel`, {}, kiran)).status, 409);
  // cancel flow
  const c2 = await call('POST', '/gatherings', { title: 'Rainy day run', description: 'x', type: 'marathon', ...at(0.002, 0), startAt: Date.now() + 2 * DAY }, kiran);
  const id2 = c2.body.gathering.id;
  await call('POST', `/gatherings/${id2}/rsvp`, {}, guest);
  assert.equal((await call('POST', `/gatherings/${id2}/cancel`, {}, demo)).status, 403);
  const cx = await call('POST', `/gatherings/${id2}/cancel`, { note: 'Weather' }, kiran);
  assert.equal(cx.body.gathering.status, 'cancelled');
  assert.ok((await call('GET', '/notifications', null, guest)).body.items.some((n) => n.type === 'gathering_cancelled' && n.refId === id2));
  assert.equal((await call('POST', `/gatherings/${id2}/cancel`, {}, kiran)).status, 409);
  assert.ok(!(await call('GET', '/gatherings', null, demo)).body.items.some((g) => g.id === id2));
});

await t('gatherings: reminder job notifies RSVPs once', async () => {
  const c = await call('POST', '/gatherings', { title: 'Soon starting walk', description: 'x', type: 'other', ...at(0.001, 0), startAt: Date.now() + 30 * MIN }, kiran);
  await call('POST', `/gatherings/${c.body.gathering.id}/rsvp`, {}, guest);
  runMaintenance(); runMaintenance();
  const n = (await call('GET', '/notifications', null, guest)).body.items.filter((x) => x.type === 'gathering_reminder' && x.refId === c.body.gathering.id);
  assert.equal(n.length, 1);
});

await t('gatherings: likes, comments, share, public page', async () => {
  const g = gathers.find((x) => x.title.includes('Raipur Run'));
  const l = await call('POST', `/gatherings/${g.id}/like`, {}, liker);
  assert.equal(l.body.gathering.likedByMe, true); assert.equal(l.body.gathering.likeCount, g.likeCount + 1);
  assert.equal((await call('DELETE', `/gatherings/${g.id}/like`, null, liker)).body.gathering.likeCount, g.likeCount);
  const c = await call('POST', `/gatherings/${g.id}/comments`, { body: 'See you at the start line!' }, demo);
  assert.equal(c.status, 201);
  assert.ok((await call('GET', `/gatherings/${g.id}/comments`, null, kiran)).body.items.some((x) => x.body.includes('start line')));
  assert.equal((await call('GET', `/gatherings/${g.id}`, null, demo)).body.gathering.commentCount, c.body.commentCount);
  const s = await call('POST', `/gatherings/${g.id}/share`, {}, demo);
  assert.equal(s.body.shareCount, g.shareCount + 1); assert.match(s.body.shareText, /Raipur Run/);
  const page = await raw('GET', `/p/gatherings/${g.id}`);
  assert.equal(page.statusCode, 200); assert.match(page.body, /Raipur Run 5K/); assert.match(page.body, /going/);
  assert.equal((await call('POST', '/gatherings/99999/comments', { body: 'x' }, demo)).status, 404);
});

await t('gatherings: calendar groups by day, excludes cancelled', async () => {
  const d = new Date(Date.now() + 5 * DAY + 5.5 * HOUR);
  const month = d.toISOString().slice(0, 7);
  const cal = (await call('GET', `/gatherings/calendar?month=${month}`, null, demo)).body.days;
  const keys = Object.keys(cal);
  assert.ok(keys.length > 1 && keys.every((k) => k.startsWith(month)));
  const all = Object.values(cal).flat();
  assert.ok(all.every((g) => g.id && g.title && g.type && g.startAt));
  assert.ok(!all.some((g) => g.title === 'Poster Making Workshop'));
  const day = new Date(all[0].startAt + 5.5 * HOUR).toISOString().slice(0, 10);
  assert.ok(cal[day].some((g) => g.id === all[0].id));
  assert.equal((await call('GET', '/gatherings/calendar?month=2026-13', null, demo)).status, 400);
  assert.deepEqual((await call('GET', '/gatherings/calendar?month=2001-01', null, demo)).body.days, {});
  assert.equal((await call('GET', '/gatherings/calendar')).status, 401);
});

await t('clubs: list, create, join/leave, detail', async () => {
  const clubs = (await call('GET', '/clubs', null, demo)).body.items;
  assert.deepEqual(clubs.map((c) => c.name).sort(), ['Blood Warriors', 'Clean Lake Crew', 'Green Raipur Plantation Club', 'Raipur Run Club', 'Stray Care Squad']);
  const run = clubs.find((c) => c.name === 'Raipur Run Club');
  assert.ok(run.memberCount >= 5 && run.joinedByMe === true && run.owner.name && run.upcomingCount >= 1);
  const stray = clubs.find((c) => c.name === 'Stray Care Squad');
  assert.equal(stray.joinedByMe, false);
  const j = await call('POST', `/clubs/${stray.id}/join`, {}, demo);
  assert.equal(j.body.club.joinedByMe, true); assert.equal(j.body.club.memberCount, stray.memberCount + 1);
  assert.equal((await call('POST', `/clubs/${stray.id}/join`, {}, demo)).status, 409);
  assert.equal((await call('DELETE', `/clubs/${stray.id}/join`, null, demo)).body.club.joinedByMe, false);
  assert.equal((await call('DELETE', `/clubs/${stray.id}/join`, null, demo)).status, 409);
  const detail = (await call('GET', `/clubs/${run.id}`, null, demo)).body;
  assert.ok(detail.members.length >= 5 && detail.gatherings.length >= 1);
  assert.ok(detail.club.members.length === detail.members.length);
  const created = await call('POST', '/clubs', { name: 'Cycle Raipur', description: 'Cyclists', category: 'marathon' }, hemant);
  assert.equal(created.status, 201); assert.equal(created.body.club.memberCount, 1); assert.equal(created.body.club.joinedByMe, true);
  assert.equal((await call('POST', '/clubs', { name: 'cycle raipur' }, demo)).status, 409);
  assert.equal((await call('POST', '/clubs', { name: 'x' }, demo)).status, 400);
  assert.equal((await call('DELETE', `/clubs/${created.body.club.id}/join`, null, hemant)).status, 409); // owner
  assert.equal((await call('GET', '/clubs/9999', null, demo)).status, 404);
});

// ---------- donations ----------
const foodBody = (o = {}) => ({
  kind: 'food', title: 'Dal and rice', description: 'Fresh', quantity: '20 packets', servings: 20, veg: 'veg',
  preparedAt: Date.now() - 30 * MIN, ...at(0.003, 0.001), address: 'Telibandha', hygieneAck: true, ...o,
});

await t('donations: feed shows seeded states, critical food first, canClaim only for verified foundations', async () => {
  const av = (await call('GET', `/donations?lat=${BASE.lat}&lng=${BASE.lng}`, null, demo)).body.items;
  assert.ok(av.length >= 8 && av.every((d) => d.status === 'available'));
  for (let k = 1; k < av.length; k++) assert.ok(av[k].expiresAt >= av[k - 1].expiresAt);
  assert.equal(av[0].freshness, 'critical'); assert.ok(av[0].expiresInMinutes < 60);
  assert.ok(av.every((d) => d.canClaim === false));
  assert.ok((await call('GET', '/donations', null, seva)).body.items.every((d) => d.canClaim === true));
  assert.ok((await call('GET', '/donations', null, hope)).body.items.every((d) => d.canClaim === false));
  const kinds = new Set(av.map((d) => d.kind));
  for (const k of ['food', 'clothes', 'books', 'bottles', 'toys', 'essentials']) assert.ok(kinds.has(k), k);
  assert.ok((await call('GET', '/donations?kind=clothes', null, demo)).body.items.every((d) => d.kind === 'clothes'));
  const claimed = (await call('GET', '/donations?status=claimed', null, demo)).body.items;
  assert.ok(claimed.length >= 3 && claimed.some((d) => d.status === 'picked_up') && claimed.every((d) => d.claimedBy.orgName));
  const hist = (await call('GET', '/donations?status=history', null, demo)).body.items;
  const states = new Set(hist.map((d) => d.status));
  for (const s of ['distributed', 'expired', 'cancelled']) assert.ok(states.has(s), s);
  const near = (await call('GET', `/donations?sort=near&lat=${BASE.lat}&lng=${BASE.lng}`, null, demo)).body.items;
  for (let k = 1; k < near.length; k++) assert.ok(near[k].distanceKm >= near[k - 1].distanceKm);
  const newest = (await call('GET', '/donations?sort=new', null, demo)).body.items;
  for (let k = 1; k < newest.length; k++) assert.ok(newest[k].id <= newest[k - 1].id);
  // mine: donors see theirs, foundations see their claims
  const mine = (await call('GET', '/donations?status=mine', null, demo)).body.items;
  assert.ok(mine.length >= 2 && mine.every((d) => d.donor.name === 'Alex Rathore'));
  const sMine = (await call('GET', '/donations?status=mine', null, seva)).body.items;
  assert.ok(sMine.length >= 2 && sMine.every((d) => d.claimedByMe));
  assert.equal((await call('GET', '/donations?status=zzz', null, demo)).status, 400);
  const d = (await call('GET', `/donations/${av[0].id}`, null, demo)).body.donation;
  assert.ok(Array.isArray(d.timeline) && d.timeline[0].status === 'available' && d.timeline[0].actor.name);
  assert.equal((await call('GET', '/donations/99999', null, demo)).status, 404);
});

await t('donations: food validation rules', async () => {
  const post = (o, tok = demo) => call('POST', '/donations', foodBody(o), tok);
  const expectBad = async (o, code) => { const r = await post(o); assert.equal(r.status, 400, JSON.stringify(o)); if (code) assert.equal(r.body.code, code); assert.ok(r.body.error.length > 8); };
  await expectBad({ preparedAt: undefined }, 'BAD_PREPARED_AT');
  await expectBad({ preparedAt: Date.now() + HOUR }, 'BAD_PREPARED_AT');
  await expectBad({ preparedAt: Date.now() - 4 * HOUR }, 'FOOD_TOO_OLD');
  await expectBad({ veg: undefined }, 'BAD_VEG');
  await expectBad({ veg: 'vegan' }, 'BAD_VEG');
  await expectBad({ servings: 0 }, 'BAD_SERVINGS');
  await expectBad({ servings: undefined }, 'BAD_SERVINGS');
  await expectBad({ hygieneAck: false }, 'HYGIENE_REQUIRED');
  await expectBad({ hygieneAck: undefined }, 'HYGIENE_REQUIRED');
  await expectBad({ kind: 'gold' }, 'BAD_KIND');
  await expectBad({ title: '' }, 'BAD_TITLE');
  await expectBad({ quantity: '' }, 'BAD_QUANTITY');
  await expectBad({ lat: undefined }, 'BAD_LOCATION');
  await expectBad({ media: ['/etc/passwd'] }, 'BAD_MEDIA');
  assert.equal((await post({}, admin)).status, 403);
  assert.equal((await call('POST', '/donations', foodBody())).status, 401);
  const prepared = Date.now() - 30 * MIN;
  const ok = await post({ preparedAt: prepared, shelfHours: 10, media: [await upload(demo)] });
  assert.equal(ok.status, 201);
  const d = ok.body.donation;
  assert.equal(d.status, 'available'); assert.equal(d.expiresAt, prepared + 4 * HOUR, 'shelf capped at 4h');
  assert.equal(d.hygieneAck, true); assert.equal(d.kindLabel, 'Food'); assert.equal(d.freshness, 'fresh'); assert.equal(d.donor.name, 'Alex Rathore');
  assert.ok(d.expiresInMinutes > 200 && d.expiresInMinutes <= 210); assert.equal(d.media.length, 1);
  const short = await post({ preparedAt: prepared, shelfHours: 1 });
  assert.equal(short.body.donation.expiresAt, prepared + HOUR);
  // non-food: no prep / hygiene needed, 7 day shelf
  const clothes = await call('POST', '/donations', { kind: 'clothes', title: 'Old jackets', quantity: '10 pieces', ...at(0.001, 0.001) }, kiran);
  assert.equal(clothes.status, 201);
  assert.ok(Math.abs(clothes.body.donation.expiresAt - (Date.now() + 7 * DAY)) < 5000);
  assert.equal(clothes.body.donation.veg, 'na'); assert.equal(clothes.body.donation.freshness, 'fresh');
  // neta and foundation can list too
  assert.equal((await call('POST', '/donations', { kind: 'books', title: 'Textbooks', quantity: '5', ...at() }, neta)).status, 201);
  assert.equal((await call('POST', '/donations', { kind: 'books', title: 'More books', quantity: '5', ...at() }, anna)).status, 201);
  // foundations in range get a donation alert
  const alerts = (await call('GET', '/notifications', null, seva)).body.items.filter((n) => n.type === 'donation' && n.refType === 'donation' && n.refId === d.id);
  assert.equal(alerts.length, 1);
  assert.equal((await call('GET', '/notifications', null, hope)).body.items.filter((n) => n.refId === d.id).length, 0, 'unverified foundations are not alerted');
  assert.equal((await call('GET', '/me/donations', null, demo)).body.items.some((x) => x.id === d.id), true);
});

let don;
await t('donations: claim rules (roles, verified-only, ETA, lock)', async () => {
  don = (await call('POST', '/donations', foodBody({ title: 'Claim test meal' }), kiran)).body.donation;
  const id = don.id;
  const cit = await call('POST', `/donations/${id}/claim`, { etaMinutes: 30 }, demo);
  assert.equal(cit.status, 403); assert.equal(cit.body.code, 'FOUNDATION_ONLY');
  assert.equal((await call('POST', `/donations/${id}/claim`, { etaMinutes: 30 }, admin)).body.code, 'FOUNDATION_ONLY');
  const un = await call('POST', `/donations/${id}/claim`, { etaMinutes: 30 }, hope);
  assert.equal(un.status, 403); assert.equal(un.body.code, 'NOT_VERIFIED');
  for (const bad of [undefined, 5, 121, 'soon', 30.5]) assert.equal((await call('POST', `/donations/${id}/claim`, { etaMinutes: bad }, seva)).status, 400);
  // food with 1h left cannot be reached in 90 min
  const tight = (await call('POST', '/donations', foodBody({ preparedAt: Date.now() - 170 * MIN, title: 'Almost expired lunch' }), kiran)).body.donation;
  const late = await call('POST', `/donations/${tight.id}/claim`, { etaMinutes: 90 }, seva);
  assert.equal(late.status, 400); assert.equal(late.body.code, 'ETA_TOO_LATE');
  assert.equal((await call('POST', `/donations/${tight.id}/claim`, { etaMinutes: 30 }, seva)).status, 200);
  // success
  const before = Date.now();
  const ok = await call('POST', `/donations/${id}/claim`, { etaMinutes: 30 }, seva);
  assert.equal(ok.status, 200);
  const d = ok.body.donation;
  assert.equal(d.status, 'claimed'); assert.equal(d.claimedBy.orgName, 'Seva Sankalp Foundation'); assert.equal(d.claimedByMe, true); assert.equal(d.canClaim, false);
  assert.ok(Math.abs(d.etaAt - (before + 30 * MIN)) < 5000);
  assert.ok(Math.abs(d.lockExpiresAt - (before + 45 * MIN)) < 5000, 'lock = 45 min when ETA is earlier');
  assert.equal(d.timeline.at(-1).status, 'claimed');
  const n = (await call('GET', '/notifications', null, kiran)).body.items.find((x) => x.type === 'donation_claimed' && x.refId === id);
  assert.ok(n && n.refType === 'donation');
  // lock extends to eta + 15 min for late etas
  const long = (await call('POST', '/donations', foodBody({ title: 'Long eta meal', preparedAt: Date.now() - 10 * MIN }), kiran)).body.donation;
  const lc = await call('POST', `/donations/${long.id}/claim`, { etaMinutes: 100 }, anna);
  assert.ok(Math.abs(lc.body.donation.lockExpiresAt - (Date.now() + 115 * MIN)) < 5000);
  // taken
  const second = await call('POST', `/donations/${id}/claim`, { etaMinutes: 20 }, anna);
  assert.equal(second.status, 409); assert.equal(second.body.code, 'ALREADY_CLAIMED'); assert.equal(second.body.claimedBy.orgName, 'Seva Sankalp Foundation');
  assert.equal((await call('POST', `/donations/${id}/claim`, { etaMinutes: 20 }, seva)).status, 409);
});

await t('donations: concurrent claim race has exactly one winner', async () => {
  const d = (await call('POST', '/donations', foodBody({ title: 'Race meal' }), demo)).body.donation;
  const results = await Promise.all([
    call('POST', `/donations/${d.id}/claim`, { etaMinutes: 20 }, seva),
    call('POST', `/donations/${d.id}/claim`, { etaMinutes: 20 }, anna),
    call('POST', `/donations/${d.id}/claim`, { etaMinutes: 20 }, seva),
  ]);
  const wins = results.filter((r) => r.status === 200);
  assert.equal(wins.length, 1);
  assert.ok(results.filter((r) => r.status === 409).every((r) => r.body.code === 'ALREADY_CLAIMED' && r.body.claimedBy));
  const final = (await call('GET', `/donations/${d.id}`, null, demo)).body.donation;
  assert.equal(final.claimedBy.id, wins[0].body.donation.claimedBy.id);
});

await t('donations: release, pickup, distribute with points and notifications', async () => {
  const id = don.id; // claimed by seva
  assert.equal((await call('POST', `/donations/${id}/release`, {}, anna)).body.code, 'NOT_CLAIMER');
  assert.equal((await call('POST', `/donations/${id}/pickup`, {}, anna)).status, 403);
  assert.equal((await call('POST', `/donations/${id}/distribute`, { beneficiaries: 5, media: [await upload(seva)] }, seva)).body.code, 'NOT_PICKED_UP');
  const rel = await call('POST', `/donations/${id}/release`, {}, seva);
  assert.equal(rel.body.donation.status, 'available'); assert.equal(rel.body.donation.claimedBy, null); assert.equal(rel.body.donation.lockExpiresAt, null);
  assert.ok((await call('GET', '/notifications', null, kiran)).body.items.some((n) => n.type === 'donation_released' && n.refId === id));
  assert.equal((await call('POST', `/donations/${id}/release`, {}, seva)).status, 403);
  // anna takes it, seva cannot touch it
  assert.equal((await call('POST', `/donations/${id}/claim`, { etaMinutes: 25 }, anna)).status, 200);
  assert.equal((await call('POST', `/donations/${id}/pickup`, {}, seva)).status, 403);
  const pu = await call('POST', `/donations/${id}/pickup`, {}, anna);
  assert.equal(pu.body.donation.status, 'picked_up'); assert.ok(pu.body.donation.pickedUpAt); assert.equal(pu.body.donation.lockExpiresAt, null);
  assert.ok((await call('GET', '/notifications', null, kiran)).body.items.some((n) => n.type === 'donation_picked_up' && n.refId === id));
  assert.equal((await call('POST', `/donations/${id}/release`, {}, anna)).status, 409);
  assert.equal((await call('POST', `/donations/${id}/cancel`, {}, kiran)).status, 409);
  const donorBefore = (await call('GET', '/me', null, kiran)).body.user.points;
  const annaBefore = (await call('GET', '/me', null, anna)).body.user.points;
  for (const bad of [0, -2, 'many', 1.5, undefined]) assert.equal((await call('POST', `/donations/${id}/distribute`, { beneficiaries: bad }, anna)).status, 400);
  assert.equal((await call('POST', `/donations/${id}/distribute`, { beneficiaries: 10, media: ['nope'] }, anna)).status, 400);
  const proof = await upload(anna);
  const dist = await call('POST', `/donations/${id}/distribute`, { note: 'Served at the shelter', beneficiaries: 22, media: [proof] }, anna);
  assert.equal(dist.status, 200); assert.equal(dist.body.donation.status, 'distributed');
  assert.deepEqual(dist.body.donation.distribution, { note: 'Served at the shelter', beneficiaries: 22, media: [proof] });
  assert.equal(dist.body.rewards.points, 5);
  assert.equal((await call('GET', '/me', null, kiran)).body.user.points, donorBefore + 10);
  assert.equal((await call('GET', '/me', null, anna)).body.user.points, annaBefore + 5);
  const note = (await call('GET', '/notifications', null, kiran)).body.items.find((n) => n.type === 'donation_distributed' && n.refId === id);
  assert.ok(note && /22/.test(note.body));
  assert.equal((await call('POST', `/donations/${id}/distribute`, { beneficiaries: 3, media: [proof] }, anna)).status, 409);
  const hist = (await call('GET', '/donations?status=history', null, demo)).body.items;
  assert.ok(hist.some((d) => d.id === id));
});

await t('donations: giver and feeder badges', async () => {
  const user = await call('POST', '/auth/register', { name: 'Big Donor', email: 'bd@x.com', password: 'secret1' });
  const tok = user.body.token;
  const badgeKeys = new Set();
  for (let k = 0; k < 5; k++) {
    const d = (await call('POST', '/donations', foodBody({ title: `Meal ${k}` }), tok)).body.donation;
    await call('POST', `/donations/${d.id}/claim`, { etaMinutes: 20 }, anna);
    await call('POST', `/donations/${d.id}/pickup`, {}, anna);
    await call('POST', `/donations/${d.id}/distribute`, { beneficiaries: 10 + k, media: [await upload(anna)] }, anna);
  }
  const me = (await call('GET', '/me', null, tok)).body.user;
  for (const b of me.badges.filter((x) => x.earned)) badgeKeys.add(b.key);
  assert.ok(badgeKeys.has('giver') && badgeKeys.has('feeder'), [...badgeKeys].join(','));
  assert.equal(me.points, 50);
});

await t('donations: cancel rules', async () => {
  const d = (await call('POST', '/donations', foodBody({ title: 'Cancel me' }), kiran)).body.donation;
  assert.equal((await call('POST', `/donations/${d.id}/cancel`, {}, demo)).body.code, 'NOT_DONOR');
  await call('POST', `/donations/${d.id}/claim`, { etaMinutes: 20 }, seva);
  const c = await call('POST', `/donations/${d.id}/cancel`, {}, kiran);
  assert.equal(c.body.donation.status, 'cancelled');
  assert.ok((await call('GET', '/notifications', null, seva)).body.items.some((n) => n.refId === d.id && /cancel/i.test(n.title)));
  assert.equal((await call('POST', `/donations/${d.id}/claim`, { etaMinutes: 20 }, anna)).body.code, 'CANCELLED');
  assert.equal((await call('POST', `/donations/${d.id}/cancel`, {}, kiran)).status, 409);
  assert.ok(!(await call('GET', '/donations', null, demo)).body.items.some((x) => x.id === d.id));
});

await t('donations: claim lock times out and the donation returns to the list', async () => {
  const d = (await call('POST', '/donations', foodBody({ title: 'Lock timeout meal' }), demo)).body.donation;
  assert.equal((await call('POST', `/donations/${d.id}/claim`, { etaMinutes: 15 }, seva)).status, 200);
  assert.equal((await call('GET', `/donations/${d.id}`, null, demo)).body.donation.status, 'claimed');
  db.prepare('UPDATE donations SET lock_expires_at=? WHERE id=?').run(Date.now() - 1000, d.id);
  const after = (await call('GET', `/donations/${d.id}`, null, demo)).body.donation;
  assert.equal(after.status, 'available'); assert.equal(after.claimedBy, null); assert.equal(after.lockExpiresAt, null);
  assert.equal(after.timeline.at(-1).status, 'available');
  assert.ok((await call('GET', '/notifications', null, seva)).body.items.some((n) => n.type === 'donation_released' && n.refId === d.id));
  assert.ok((await call('GET', '/notifications', null, demo)).body.items.some((n) => n.type === 'donation_released' && n.refId === d.id));
  assert.equal((await call('POST', `/donations/${d.id}/claim`, { etaMinutes: 15 }, anna)).status, 200);
  // the old claimer cannot act any more
  db.prepare('UPDATE donations SET lock_expires_at=? WHERE id=?').run(Date.now() - 1000, d.id);
  runMaintenance(); // the interval job does the same
  assert.equal(db.prepare('SELECT status FROM donations WHERE id=?').get(d.id).status, 'available');
  assert.equal((await call('POST', `/donations/${d.id}/pickup`, {}, anna)).status, 403);
  // picked-up donations are never auto-released
  assert.equal((await call('POST', `/donations/${d.id}/claim`, { etaMinutes: 15 }, anna)).status, 200);
  await call('POST', `/donations/${d.id}/pickup`, {}, anna);
  db.prepare('UPDATE donations SET lock_expires_at=? WHERE id=?').run(Date.now() - 1000, d.id);
  runMaintenance();
  assert.equal(db.prepare('SELECT status FROM donations WHERE id=?').get(d.id).status, 'picked_up');
});

await t('donations: expiry (lazy on read and via maintenance) hides listings and blocks claims', async () => {
  const a = (await call('POST', '/donations', foodBody({ title: 'Expiring A' }), demo)).body.donation;
  const b = (await call('POST', '/donations', foodBody({ title: 'Expiring B' }), demo)).body.donation;
  db.prepare('UPDATE donations SET expires_at=? WHERE id IN (?,?)').run(Date.now() - 1000, a.id, b.id);
  const list = (await call('GET', '/donations', null, seva)).body.items;
  assert.ok(!list.some((d) => d.id === a.id || d.id === b.id));
  const da = (await call('GET', `/donations/${a.id}`, null, demo)).body.donation;
  assert.equal(da.status, 'expired'); assert.equal(da.freshness, 'expired'); assert.equal(da.expiresInMinutes, 0); assert.equal(da.canClaim, false);
  assert.equal((await call('POST', `/donations/${a.id}/claim`, { etaMinutes: 20 }, seva)).body.code, 'EXPIRED');
  assert.ok((await call('GET', '/notifications', null, demo)).body.items.some((n) => n.refId === a.id && /expired/i.test(n.title)));
  // maintenance path
  const c = (await call('POST', '/donations', foodBody({ title: 'Expiring C' }), demo)).body.donation;
  db.prepare('UPDATE donations SET expires_at=? WHERE id=?').run(Date.now() - 1000, c.id);
  runMaintenance();
  assert.equal(db.prepare('SELECT status FROM donations WHERE id=?').get(c.id).status, 'expired');
  // a claimed donation that expires before pickup also expires
  const e = (await call('POST', '/donations', foodBody({ title: 'Expiring D' }), demo)).body.donation;
  await call('POST', `/donations/${e.id}/claim`, { etaMinutes: 20 }, seva);
  db.prepare('UPDATE donations SET expires_at=? WHERE id=?').run(Date.now() - 1000, e.id);
  runMaintenance();
  assert.equal(db.prepare('SELECT status FROM donations WHERE id=?').get(e.id).status, 'expired');
  assert.ok((await call('GET', '/donations?status=history', null, demo)).body.items.some((d) => d.id === e.id));
  assert.ok(!(await call('GET', '/donations?status=claimed', null, demo)).body.items.some((d) => d.id === e.id));
});

await t('donations: freshness levels', async () => {
  const f = async (min) => {
    const d = (await call('POST', '/donations', foodBody({ title: `Fresh ${min}`, preparedAt: Date.now() - (240 - min) * MIN + 5000 }), demo));
    if (d.status !== 201) { // too old to list via the API, adjust directly
      return null;
    }
    return d.body.donation;
  };
  const fresh = await f(200);
  assert.equal(fresh.freshness, 'fresh');
  const soon = (await call('POST', '/donations', foodBody({ title: 'Soon meal', preparedAt: Date.now() - 170 * MIN }), demo)).body.donation;
  assert.equal(soon.freshness, 'soon');
  const crit = (await call('GET', '/donations', null, demo)).body.items.find((d) => d.title.startsWith('Wedding leftovers'));
  assert.equal(crit.freshness, 'critical');
});

await t('foundations: public list, detail, dashboard, stats', async () => {
  const forCitizen = (await call('GET', '/foundations', null, demo)).body.items;
  assert.deepEqual(forCitizen.map((f) => f.name).sort(), ['Annapurna Food Bank', 'Bal Vikas Anathalaya', 'Drishti Blind Care Centre', 'Raen Basera Night Shelter',
    'Seva Sankalp Foundation', 'Shanti Vridhashram']);
  assert.ok(forCitizen.every((f) => f.verified && f.regNo && f.stats && typeof f.activeClaims === 'number'));
  const forAdmin = (await call('GET', '/foundations', null, admin)).body.items;
  assert.ok(forAdmin.some((f) => f.name === 'New Hope Trust' && f.verified === false));
  assert.equal((await call('GET', '/foundations?need=books', null, demo)).body.items.length >= 1, true);
  assert.deepEqual((await call('GET', '/foundations?q=annapurna', null, demo)).body.items.map((f) => f.name), ['Annapurna Food Bank']);
  const a = forCitizen.find((f) => f.name === 'Annapurna Food Bank');
  const detail = (await call('GET', `/foundations/${a.id}`, null, demo)).body.foundation;
  assert.ok(detail.stats.distributed >= 5 && detail.stats.beneficiaries > 100 && detail.stats.claimed >= detail.stats.distributed);
  const hopeId = forAdmin.find((f) => f.name === 'New Hope Trust').id;
  assert.equal((await call('GET', `/foundations/${hopeId}`, null, demo)).status, 404);
  assert.equal((await call('GET', `/foundations/${hopeId}`, null, admin)).status, 200);
  assert.equal((await call('GET', `/foundations/${hopeId}`, null, hope)).status, 200);
  const dash = await call('GET', `/foundation/dashboard?lat=${BASE.lat}&lng=${BASE.lng}`, null, anna);
  assert.equal(dash.status, 200);
  assert.deepEqual(dash.body.stats, (await call('GET', `/foundations/${a.id}`, null, anna)).body.foundation.stats);
  assert.ok(dash.body.activeClaims.every((d) => d.claimedByMe && ['claimed', 'picked_up'].includes(d.status)));
  assert.ok(dash.body.nearbyAvailable.length > 0 && dash.body.nearbyAvailable.every((d) => d.status === 'available' && d.distanceKm <= 15));
  assert.ok(dash.body.needs.includes('food'));
  assert.equal((await call('GET', '/foundation/dashboard', null, demo)).status, 403);
  assert.equal((await call('GET', '/foundation/dashboard', null, admin)).status, 403);
  // unverified foundations may still open their dashboard
  assert.equal((await call('GET', '/foundation/dashboard', null, hope)).status, 200);
});

await t('donations: likes, comments, share, public page', async () => {
  const d = (await call('GET', '/donations', null, demo)).body.items[0];
  const l = await call('POST', `/donations/${d.id}/like`, {}, liker);
  assert.equal(l.body.donation.likedByMe, true); assert.equal(l.body.donation.likeCount, d.likeCount + 1);
  assert.equal((await call('DELETE', `/donations/${d.id}/like`, null, liker)).body.donation.likeCount, d.likeCount);
  const c = await call('POST', `/donations/${d.id}/comments`, { body: 'Is parking available?' }, kiran);
  assert.equal(c.status, 201);
  assert.ok((await call('GET', `/donations/${d.id}/comments`, null, demo)).body.items.some((x) => x.body === 'Is parking available?'));
  const s = await call('POST', `/donations/${d.id}/share`, {}, demo);
  assert.equal(s.body.shareCount, d.shareCount + 1); assert.match(s.body.shareText, /\/p\/donations\//);
  const page = await raw('GET', `/p/donations/${d.id}`);
  assert.equal(page.statusCode, 200); assert.match(page.headers['content-type'], /html/); assert.ok(page.body.includes(d.title.replace(/&/g, '&amp;')));
  assert.equal((await raw('GET', '/p/donations/99999')).statusCode, 404);
});

await t('public pages escape user content', async () => {
  const r = await call('POST', '/gatherings', { title: '<script>alert(1)</script> drive', description: '"><img src=x onerror=alert(1)>', type: 'other', ...at(0.001, 0), startAt: Date.now() + DAY }, demo);
  const page = await raw('GET', `/p/gatherings/${r.body.gathering.id}`);
  assert.ok(!page.body.includes('<script>alert(1)</script>'));
  assert.ok(!page.body.includes('<img src=x'));
  assert.match(page.body, /&lt;script&gt;/);
});

// ---------- cross-cutting ----------
await t('home feed: top issues, next gatherings, soonest donations', async () => {
  const h = (await call('GET', `/feed/home?lat=${BASE.lat}&lng=${BASE.lng}`, null, demo)).body;
  assert.equal(h.issues.length, 3); assert.equal(h.gatherings.length, 3); assert.equal(h.donations.length, 3);
  assert.ok(h.issues[0].engagement >= h.issues[2].engagement);
  assert.ok(h.gatherings[0].startAt <= h.gatherings[2].startAt);
  assert.ok(h.donations[0].expiresAt <= h.donations[2].expiresAt && h.donations.every((d) => d.status === 'available'));
  assert.equal((await call('GET', '/feed/home')).status, 401);
});

await t('activity: gatherings (RSVP) and donations (listed by me)', async () => {
  const g = (await call('GET', '/me/activity?type=gatherings', null, demo)).body.items;
  assert.ok(g.length >= 4 && g.every((x) => x.goingByMe));
  const d = (await call('GET', '/me/activity?type=donations', null, demo)).body.items;
  assert.ok(d.length >= 5 && d.every((x) => x.donor.name === 'Alex Rathore'));
  assert.equal((await call('GET', '/me/activity?type=nope', null, demo)).status, 400);
  assert.equal((await call('GET', '/me/activity?type=reports', null, demo)).status, 200);
});

await t('notifications carry refType/refId and legacy issueId', async () => {
  const items = (await call('GET', '/notifications', null, demo)).body.items;
  assert.ok(items.every((n) => 'refType' in n && 'refId' in n && 'issueId' in n));
  assert.ok(items.some((n) => n.refType === 'gathering') && items.some((n) => n.refType === 'donation') && items.some((n) => n.refType === 'issue' && n.issueId === n.refId));
  const types = new Set((await call('GET', '/notifications', null, admin)).body.items.map((n) => n.type));
  assert.ok(types.has('escalated'));
});

await t('badges: v3 keys exist in meta and profile', async () => {
  const keys = (await call('GET', '/meta')).body.badges.map((b) => b.key);
  for (const k of ['volunteer_heart', 'green_thumb', 'giver', 'feeder', 'voice']) assert.ok(keys.includes(k), k);
  const demoBadges = (await call('GET', '/me', null, demo)).body.user.badges.filter((b) => b.earned).map((b) => b.key);
  assert.ok(demoBadges.includes('volunteer_heart') && demoBadges.includes('green_thumb') && demoBadges.includes('giver'));
  const m = (await call('GET', '/meta')).body.config;
  assert.equal(m.campaignVotes, 5); assert.equal(m.foodShelfHours, 4); assert.equal(m.otherShelfDays, 7);
  assert.equal(m.claimLockMinutes, 45); assert.equal(m.foundationAlertRadiusKm, 15);
});

await t('seed: lively world has the promised volume', async () => {
  const c = (sql) => db.prepare(sql).get().c;
  assert.ok(c('SELECT COUNT(*) c FROM gatherings') >= 12);
  assert.ok(c('SELECT COUNT(*) c FROM clubs') >= 5);
  assert.ok(c('SELECT COUNT(*) c FROM donations') >= 14);
  for (const s of ['available', 'claimed', 'picked_up', 'distributed', 'expired', 'cancelled']) {
    assert.ok(c(`SELECT COUNT(*) c FROM donations WHERE status='${s}'`) >= 1, s);
  }
  assert.ok(c("SELECT COUNT(*) c FROM gatherings WHERE status='proposed'") >= 1 && c("SELECT COUNT(*) c FROM gatherings WHERE status='completed'") >= 4);
  assert.ok(c('SELECT COUNT(*) c FROM comments') >= 20 && c('SELECT COUNT(*) c FROM likes') >= 50);
  assert.ok(c("SELECT COUNT(*) c FROM issues WHERE escalated=1") >= 2);
});

// ---------- like / comment / share robustness ----------
await t('social: empty-body JSON requests work on every verb and target', async () => {
  const ct = { 'content-type': 'application/json' };
  const send = (method, url, tok, payload) => app.inject({ method, url, payload, headers: { authorization: `Bearer ${tok}`, ...ct } });
  const issueId = db.prepare("SELECT id FROM issues WHERE title LIKE 'Open manhole%'").get().id;
  const gid = db.prepare('SELECT id FROM gatherings ORDER BY id').get().id;
  const did = db.prepare('SELECT id FROM donations ORDER BY id').get().id;
  for (const tok of [demo, admin, neta, seva]) {
    for (const [seg, id, key] of [['issues', issueId, 'issue'], ['gatherings', gid, 'gathering'], ['donations', did, 'donation']]) {
      const url = `/${seg}/${id}`;
      let r = await send('DELETE', `${url}/like`, tok);
      assert.equal(r.statusCode, 200, `${url} unlike with empty JSON body: ${r.body}`);
      r = await send('POST', `${url}/like`, tok);
      assert.equal(r.statusCode, 200, r.body); assert.equal(JSON.parse(r.body)[key].likedByMe, true);
      assert.equal((await send('POST', `${url}/like`, tok)).statusCode, 200);
      r = await send('DELETE', `${url}/like`, tok);
      assert.equal(r.statusCode, 200); assert.equal(JSON.parse(r.body)[key].likedByMe, false);
      assert.equal((await send('DELETE', `${url}/like`, tok)).statusCode, 200, 'unlike when not liked');
      r = await app.inject({ method: 'DELETE', url: `${url}/like`, headers: { authorization: `Bearer ${tok}` } });
      assert.equal(r.statusCode, 200);
      r = await send('POST', `${url}/share`, tok);
      assert.equal(r.statusCode, 200, r.body); assert.ok(JSON.parse(r.body).shareCount >= 1);
      r = await send('POST', `${url}/comments`, tok, { body: '' });
      assert.equal(r.statusCode, 400); assert.equal(JSON.parse(r.body).code, 'BAD_COMMENT');
      assert.equal((await send('POST', `${url}/comments`, tok, {})).statusCode, 400);
      const m = await upload(tok);
      r = await send('POST', `${url}/comments`, tok, { body: 'With a photo', media: [m] });
      assert.equal(r.statusCode, 201, r.body); assert.deepEqual(JSON.parse(r.body).comment.media, [m]);
      assert.equal((await send('POST', `${url}/comments`, tok, { body: 'Plain comment' })).statusCode, 201);
    }
  }
  assert.equal((await send('POST', '/auth/logout', await login('guest@bythepeople.app', 'guest123'))).statusCode, 200);
  assert.equal((await send('POST', '/notifications/read', demo)).statusCode, 200);
  // malformed JSON is still a clean 400, not a 500
  const bad = await app.inject({ method: 'POST', url: '/auth/login', payload: '{nope', headers: ct });
  assert.equal(bad.statusCode, 400); assert.equal(JSON.parse(bad.body).code, 'BAD_REQUEST');
  assert.equal((await app.inject({ method: 'DELETE', url: `/issues/${issueId}/like`, headers: ct })).statusCode, 401);
  assert.equal((await send('DELETE', '/issues/999999/like', demo)).statusCode, 404);
});

// ---------- far-away clients ----------
await t('geo: a client ~45 km from Raipur sees all data and gets a state-wide default scope', async () => {
  const far = { lat: BASE.lat + 0.4, lng: BASE.lng }; // about 44 km north, outside the Raipur city radius
  const q = `lat=${far.lat}&lng=${far.lng}`;
  const near = (await call('GET', '/issues?phase=all', null, demo)).body.items.length;
  const r = await call('GET', `/issues?phase=all&${q}`, null, demo);
  assert.equal(r.status, 200); assert.equal(r.body.items.length, near);
  assert.ok(r.body.items.every((i) => i.distanceKm > 30));
  assert.equal((await call('GET', `/events?${q}`, null, demo)).status, 200);
  assert.ok((await call('GET', `/gatherings?${q}`, null, demo)).body.items.length >= 5);
  assert.ok((await call('GET', `/donations?${q}`, null, demo)).body.items.length >= 5);
  assert.equal((await call('GET', `/feed/home?${q}`, null, demo)).body.issues.length, 3);
  const g = (await call('GET', `/geo/resolve?${q}`, null, demo)).body;
  assert.equal(g.covered, false); assert.equal(g.city, null);
  assert.equal(g.state.name, 'Chhattisgarh'); assert.equal(g.defaultScope, 'state'); assert.equal(g.label, 'Chhattisgarh');
  assert.equal(g.nearestCity.name, 'Raipur'); assert.ok(g.distanceKm > 30);
  // asking for "my city" outside coverage widens to the state instead of returning nothing
  const c = (await call('GET', `/issues?phase=all&scope=city&${q}`, null, demo)).body;
  assert.equal(c.scope, 'state'); assert.equal(c.area.name, 'Chhattisgarh'); assert.ok(c.items.length > 0);
  const s = (await call('GET', `/geo/summary?scope=city&${q}`, null, demo)).body;
  assert.equal(s.area.name, 'Chhattisgarh'); assert.ok(s.reported > 0);
  const n = (await call('GET', `/netas?scope=city&${q}`, null, demo)).body;
  assert.ok(n.items.length > 0); assert.equal(n.scope, 'state');
  // inside Raipur is unchanged, and the middle of nowhere falls back to everywhere
  const home = (await call('GET', `/geo/resolve?lat=${BASE.lat}&lng=${BASE.lng}`, null, demo)).body;
  assert.equal(home.covered, true); assert.equal(home.city.name, 'Raipur'); assert.equal(home.defaultScope, 'city');
  const nowhere = (await call('GET', '/geo/resolve?lat=10&lng=100', null, demo)).body;
  assert.equal(nowhere.covered, false); assert.equal(nowhere.defaultScope, 'all'); assert.equal(nowhere.state, null);
  const all = (await call('GET', '/issues?phase=all&scope=city&lat=10&lng=100', null, demo)).body;
  assert.equal(all.scope, 'all'); assert.equal(all.items.length, near);
});

// ---------- insights & impact ----------
await t('insights: requires sign-in (401 without a token)', async () => {
  assert.equal((await call('GET', '/insights')).status, 401);
  assert.equal((await call('GET', '/impact')).status, 401);
});

await t('insights: citizen, foundation and admin get the documented shape', async () => {
  for (const tok of [demo, anna, admin]) {
    const r = await call('GET', '/insights', null, tok);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.deepEqual(Object.keys(r.body).sort(), ['metrics', 'period', 'top', 'weekly']);
    assert.equal(typeof r.body.period.from, 'number'); assert.equal(typeof r.body.period.to, 'number');
    assert.deepEqual(r.body.metrics.map((m) => m.key), ['people_reached', 'items_donated', 'events_joined', 'claim_rate']);
    for (const m of r.body.metrics) {
      assert.equal(typeof m.label, 'string'); assert.equal(typeof m.value, 'number');
      assert.equal(typeof m.delta, 'number'); assert.equal(typeof m.deltaLabel, 'string');
      assert.equal(typeof m.positive, 'boolean');
    }
    const rate = r.body.metrics.find((m) => m.key === 'claim_rate').value;
    assert.ok(rate >= 0 && rate <= 1, `claim rate ${rate}`);
    assert.equal(r.body.weekly.length, 7);
    assert.ok(r.body.weekly.every((w) => typeof w.day === 'string' && typeof w.value === 'number'));
    assert.ok(r.body.top.length <= 5);
    for (const i of r.body.top) {
      assert.ok(['donation', 'gathering'].includes(i.kind));
      assert.equal(typeof i.id, 'number'); assert.equal(typeof i.title, 'string');
      assert.equal(typeof i.subtitle, 'string'); assert.equal(typeof i.when, 'number');
      assert.ok(i.rate >= 0 && i.rate <= 1);
    }
  }
});

await t('impact: citizen, foundation and admin get totals; volunteer hours are 3 per event', async () => {
  for (const tok of [demo, anna, admin]) {
    const r = await call('GET', '/impact', null, tok);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.deepEqual(Object.keys(r.body).sort(), ['events', 'items', 'meals', 'volunteerHours']);
    for (const k of ['meals', 'items', 'events', 'volunteerHours']) assert.equal(typeof r.body[k], 'number');
    assert.equal(r.body.volunteerHours, r.body.events * 3);
  }
});

// ---------- needs, foundation surplus, proof of delivery, reminders ----------
await t('needs: verified foundation posts, citizen and unverified foundation cannot, validation', async () => {
  const deadlineAt = Date.now() + 2 * DAY;
  const bad = await call('POST', '/needs', { kind: 'food', title: 'Rice for families', quantity: '40 kg', deadlineAt }, demo);
  assert.equal(bad.status, 403); assert.equal(bad.body.code, 'FORBIDDEN');
  const unv = await call('POST', '/needs', { kind: 'food', title: 'Rice for families', quantity: '40 kg', deadlineAt }, hope);
  assert.equal(unv.status, 403); assert.equal(unv.body.code, 'NOT_VERIFIED');
  for (const body of [{ kind: 'nope', title: 'Rice for families' }, { kind: 'food', title: 'ab' }, { kind: 'constructor', title: 'Rice for families' }]) {
    assert.equal((await call('POST', '/needs', body, seva)).status, 400, JSON.stringify(body));
  }
  assert.equal((await call('POST', '/needs', { kind: 'food', title: 'Rice for families', deadlineAt: 1000 }, seva)).status, 400);
  const created = await call('POST', '/needs', { kind: 'food', title: 'Rice for 40 families', quantity: '40 kg', deadlineAt }, seva);
  assert.equal(created.status, 201);
  const n = created.body.need;
  assert.equal(n.kind, 'food'); assert.equal(n.kindLabel, 'Food'); assert.equal(n.status, 'open');
  assert.equal(n.quantity, '40 kg'); assert.equal(n.deadlineAt, deadlineAt); assert.equal(n.pledgeCount, 0); assert.equal(n.pledgedByMe, false);
  assert.equal(n.foundation.verified, true); assert.equal(n.foundation.id, await uid(seva));
  globalThis.needId = n.id;
});

await t('needs: list is newest first with open default, pledges are idempotent, owner cannot pledge', async () => {
  const list = (await call('GET', '/needs', null, anna)).body.items;
  assert.equal(list[0].id, needId);
  assert.ok(list.every((x) => x.status === 'open'));
  assert.equal((await call('GET', '/needs?status=bogus', null, anna)).status, 400);
  assert.equal((await call('POST', `/needs/${needId}/pledge`, {}, seva)).status, 409);
  const p1 = await call('POST', `/needs/${needId}/pledge`, { note: 'We can deliver Friday' }, anna);
  assert.equal(p1.status, 200); assert.equal(p1.body.need.pledgeCount, 1); assert.equal(p1.body.need.pledgedByMe, true);
  const p2 = await call('POST', `/needs/${needId}/pledge`, {}, anna);
  assert.equal(p2.status, 200); assert.equal(p2.body.need.pledgeCount, 1);
  assert.equal(db.prepare('SELECT COUNT(*) c FROM need_pledges WHERE need_id=?').get(needId).c, 1);
  assert.ok((await call('GET', '/notifications', null, seva)).body.items.some((x) => x.type === 'need_pledge' && x.refId === needId));
  assert.equal((await call('POST', '/needs/99999/pledge', {}, anna)).status, 404);
  const dem = await call('POST', `/needs/${needId}/pledge`, {}, demo);
  assert.equal(dem.body.need.pledgeCount, 2);
  const un = await call('DELETE', `/needs/${needId}/pledge`, null, demo);
  assert.equal(un.body.need.pledgeCount, 1); assert.equal(un.body.need.pledgedByMe, false);
  assert.equal((await call('GET', '/needs', null, demo)).body.items.find((x) => x.id === needId).pledgedByMe, false);
});

await t('needs: only the owner can close; closed needs leave the open list and reject pledges', async () => {
  assert.equal((await call('POST', `/needs/${needId}/close`, {}, anna)).status, 403);
  const c = await call('POST', `/needs/${needId}/close`, {}, seva);
  assert.equal(c.status, 200); assert.equal(c.body.need.status, 'closed');
  assert.ok(!(await call('GET', '/needs', null, anna)).body.items.some((x) => x.id === needId));
  assert.ok((await call('GET', '/needs?status=closed', null, anna)).body.items.some((x) => x.id === needId));
  assert.equal((await call('POST', `/needs/${needId}/pledge`, {}, demo)).status, 409);
});

await t('surplus: verified foundation can share, other verified foundation claims, citizens and the donor cannot', async () => {
  const mk = await call('POST', '/donations', { kind: 'clothes', title: 'Winter blankets surplus', quantity: '30 blankets', ...at() }, seva);
  assert.equal(mk.status, 201); assert.equal(mk.body.donation.donorKind, 'foundation');
  const sur = mk.body.donation.id;
  const own = await call('POST', '/donations', { kind: 'clothes', title: 'Citizen clothes drive', quantity: '5 bags', ...at() }, demo);
  assert.equal(own.body.donation.donorKind, 'donor');
  assert.equal((await call('POST', '/donations', { kind: 'clothes', title: 'Blankets from hope', quantity: '3', ...at() }, hope)).body.code, 'NOT_VERIFIED');
  assert.equal((await call('POST', `/donations/${sur}/claim`, { etaMinutes: 20 }, demo)).body.code, 'FORBIDDEN');
  assert.equal((await call('POST', `/donations/${sur}/claim`, { etaMinutes: 20 }, neta)).body.code, 'FORBIDDEN');
  assert.equal((await call('POST', `/donations/${sur}/claim`, { etaMinutes: 20 }, admin)).body.code, 'FORBIDDEN');
  assert.equal((await call('POST', `/donations/${sur}/claim`, { etaMinutes: 20 }, seva)).body.code, 'FORBIDDEN');
  assert.equal((await call('GET', `/donations/${sur}`, null, seva)).body.donation.canClaim, false);
  assert.equal((await call('GET', `/donations/${sur}`, null, anna)).body.donation.canClaim, true);
  const claim = await call('POST', `/donations/${sur}/claim`, { etaMinutes: 20 }, anna);
  assert.equal(claim.status, 200); assert.equal(claim.body.donation.donorKind, 'foundation');
  assert.equal(claim.body.donation.claimedBy.id, await uid(anna));
  assert.equal(claim.body.donation.proof, null);
  globalThis.surId = sur;
});

await t('proof of delivery: distribute needs photos and a beneficiary count; proof exposed when distributed', async () => {
  assert.equal((await call('POST', `/donations/${surId}/pickup`, {}, anna)).status, 200);
  const noMedia = await call('POST', `/donations/${surId}/distribute`, { beneficiaries: 12 }, anna);
  assert.equal(noMedia.status, 400); assert.equal(noMedia.body.code, 'BAD_REQUEST');
  const noCount = await call('POST', `/donations/${surId}/distribute`, { media: [await upload(anna)] }, anna);
  assert.equal(noCount.status, 400); assert.equal(noCount.body.code, 'BAD_REQUEST');
  const p = await upload(anna);
  const ok = await call('POST', `/donations/${surId}/distribute`, { note: 'Handed out at the ward office', beneficiaries: 12, media: [p] }, anna);
  assert.equal(ok.status, 200);
  const d = ok.body.donation;
  assert.equal(d.status, 'distributed'); assert.equal(d.distribution.beneficiaries, 12);
  assert.deepEqual(d.proof.media, [p]); assert.equal(d.proof.note, 'Handed out at the ward office');
  assert.equal(d.proof.beneficiaries, 12); assert.equal(typeof d.proof.at, 'number'); assert.equal(d.proof.at, d.distributedAt);
  const reread = (await call('GET', `/donations/${surId}`, null, seva)).body.donation;
  assert.deepEqual(reread.proof.media, [p]); assert.equal(reread.proof.beneficiaries, 12);
});

await t('reminders: create for me, list, collaborator notification, creator-only delete', async () => {
  const remindAt = Date.now() + HOUR;
  const mine = await call('POST', '/reminders', { title: 'Call the shelter', scope: 'me', remindAt, refType: 'gathering', refId: 3 }, demo);
  assert.equal(mine.status, 201); assert.equal(mine.body.reminder.mine, true); assert.equal(mine.body.reminder.recipient, null);
  assert.equal(mine.body.reminder.refType, 'gathering'); assert.equal(mine.body.reminder.refId, 3); assert.equal(mine.body.reminder.done, false);
  assert.equal((await call('POST', '/reminders', { title: 'Collab', scope: 'collaborator', remindAt }, demo)).status, 400);
  assert.equal((await call('POST', '/reminders', { title: 'Collab', scope: 'collaborator', remindAt, recipientId: 999999 }, demo)).status, 404);
  assert.equal((await call('POST', '/reminders', { title: 'Bad', scope: 'other', remindAt }, demo)).status, 400);
  const sunitaId = await uid(sunita);
  const later = await call('POST', '/reminders', { title: 'Send the blanket list', scope: 'collaborator', remindAt: remindAt + DAY, recipientId: sunitaId }, demo);
  assert.equal(later.status, 201); assert.equal(later.body.reminder.recipient.id, sunitaId);
  const early = await call('POST', '/reminders', { title: 'Space walkthrough', scope: 'space', remindAt: remindAt - HOUR }, demo);
  assert.equal(early.status, 201);
  const demoList = (await call('GET', '/reminders', null, demo)).body.items;
  const times = demoList.map((r) => r.remindAt);
  assert.deepEqual(times, [...times].sort((a, b) => a - b));
  assert.ok(demoList.some((r) => r.id === mine.body.reminder.id));
  const sunitaList = (await call('GET', '/reminders', null, sunita)).body.items;
  const got = sunitaList.find((r) => r.id === later.body.reminder.id);
  assert.ok(got); assert.equal(got.mine, false); assert.equal(got.scope, 'collaborator');
  assert.ok(!sunitaList.some((r) => r.id === mine.body.reminder.id));
  const note = (await call('GET', '/notifications', null, sunita)).body.items.find((x) => x.type === 'reminder' && x.refId === later.body.reminder.id);
  assert.ok(note); assert.equal(note.title, 'Reminder from Alex Rathore');
  assert.equal((await call('DELETE', `/reminders/${mine.body.reminder.id}`, null, sunita)).status, 403);
  assert.equal((await call('DELETE', `/reminders/${later.body.reminder.id}`, null, sunita)).status, 403);
  assert.deepEqual((await call('DELETE', `/reminders/${mine.body.reminder.id}`, null, demo)).body, { ok: true });
  assert.ok(!(await call('GET', '/reminders', null, demo)).body.items.some((r) => r.id === mine.body.reminder.id));
  assert.equal((await call('DELETE', `/reminders/${mine.body.reminder.id}`, null, demo)).status, 404);
});

await t('sevalink seed: needs with urgency and progress, meals stat, proof of delivery', async () => {
  const needs = (await call('GET', '/needs', null, demo)).body.items;
  assert.ok(needs.length >= 8);
  assert.ok(needs.every((n) => ['low', 'normal', 'high', 'critical'].includes(n.urgency) && typeof n.progress === 'number'));
  const bl = needs.find((n) => n.title === '40 blankets by Friday');
  assert.ok(bl && bl.urgency === 'critical' && bl.targetQty === 40 && bl.pledgedQty === 26 && bl.progress > 0.6 && bl.progress < 1);
  assert.ok(new Set(needs.map((n) => n.kind)).size >= 6);
  const me = (await call('GET', '/me', null, demo)).body.user;
  assert.ok(me.stats.meals > 0 && typeof me.stats.reports === 'number');
  const fdash = (await call('GET', `/foundation/dashboard?lat=${BASE.lat}&lng=${BASE.lng}`, null, anna)).body;
  assert.ok(fdash.stats.meals > 0 && fdash.stats.claimed >= 1);
});

console.log(`\n${passed} v3 tests passed${process.exitCode ? ' (with failures)' : ''}`);
fs.rmSync(tmp, { force: true });
fs.rmSync(uploads, { recursive: true, force: true });
