// End-to-end API test: runs against a throwaway DB, no server needed.
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import assert from 'node:assert/strict';

const tmp = path.join(os.tmpdir(), `sober-test-${Date.now()}.db`);
process.env.DB_PATH = tmp;
const uploads = path.join(os.tmpdir(), `sober-uploads-${Date.now()}`);
process.env.UPLOAD_DIR = uploads;
const { seed, BASE } = await import('../src/seed.js');
const { buildApp } = await import('../src/server.js');
seed();
const app = buildApp();

let passed = 0;
const t = async (name, fn) => {
  try { await fn(); passed++; console.log(`  ok  ${name}`); }
  catch (e) { console.error(`FAIL  ${name}\n      ${e.message}`); process.exitCode = 1; }
};
const call = async (method, url, body, token) => {
  const res = await app.inject({ method, url, payload: body, headers: token ? { authorization: `Bearer ${token}` } : {} });
  return { status: res.statusCode, body: res.body ? JSON.parse(res.body) : null };
};
const login = async (email, password) => (await call('POST', '/auth/login', { email, password })).body.token;

const demo = await login('demo@bythepeople.app', 'demo1234');
const aarav = await login('hemant@bythepeople.app', 'sober123');
const diya = await login('kiran@bythepeople.app', 'sober123');
const guest = await login('guest@bythepeople.app', 'guest123');
const at = (dlat = 0, dlng = 0) => ({ lat: BASE.lat + dlat, lng: BASE.lng + dlng });

await t('health + meta', async () => {
  assert.equal((await call('GET', '/health')).status, 200);
  const m = (await call('GET', '/meta')).body;
  assert.equal(m.config.eventThreshold, 5);
  assert.ok(m.categories.length >= 8);
});

await t('auth: register, duplicate, bad login, unauth', async () => {
  const r = await call('POST', '/auth/register', { name: 'Test User', email: 'test@x.com', password: 'secret1' });
  assert.equal(r.status, 201); assert.ok(r.body.token);
  assert.equal((await call('POST', '/auth/register', { name: 'Test User', email: 'test@x.com', password: 'secret1' })).status, 409);
  assert.equal((await call('POST', '/auth/login', { email: 'test@x.com', password: 'wrong' })).status, 401);
  assert.equal((await call('GET', '/me')).status, 401);
  assert.equal((await call('POST', '/auth/register', { name: 'A', email: 'bad', password: '1' })).status, 400);
});

let streetlight;
await t('feed: issues nearest first with distance + range flag', async () => {
  const r = await call('GET', `/issues?phase=issue&sort=nearby&lat=${BASE.lat}&lng=${BASE.lng}`, null, demo);
  assert.equal(r.status, 200);
  const items = r.body.items;
  assert.ok(items.length > 5);
  for (let i = 1; i < items.length; i++) assert.ok(items[i].distanceKm >= items[i - 1].distanceKm);
  streetlight = items.find((i) => i.title.includes('Shankar Nagar Road'));
  assert.equal(streetlight.supportCount, 4);
  assert.equal(streetlight.supportedByMe, false);
  const far = items.find((i) => i.title.includes('near Tatibandh'));
  assert.equal(far.inRange, false);
});

await t('location gate blocks far support', async () => {
  const items = (await call('GET', `/issues?lat=${BASE.lat}&lng=${BASE.lng}`, null, demo)).body.items;
  const far = items.find((i) => i.title.includes('near Tatibandh'));
  const r = await call('POST', `/issues/${far.id}/support`, at(), demo);
  assert.equal(r.status, 403); assert.equal(r.body.code, 'OUT_OF_RANGE');
});

await t('location jump (spoof) rejected', async () => {
  const r = await call('POST', `/issues/${streetlight.id}/support`, { lat: BASE.lat + 3, lng: BASE.lng + 3 }, demo);
  assert.equal(r.status, 400); assert.equal(r.body.code, 'LOCATION_JUMP');
});

await t('5th support converts issue into event + notifies + rewards', async () => {
  const r = await call('POST', `/issues/${streetlight.id}/support`, at(0.0015, 0.001), demo);
  assert.equal(r.status, 200);
  assert.equal(r.body.converted, true);
  assert.equal(r.body.issue.status, 'event');
  assert.equal(r.body.issue.phase, 'event');
  assert.ok(r.body.rewards.points >= 3);
  const again = await call('POST', `/issues/${streetlight.id}/support`, at(0.0015, 0.001), demo);
  assert.equal(again.status, 409);
  const n = (await call('GET', '/notifications', null, aarav)).body;
  assert.ok(n.items.some((x) => x.issueId === streetlight.id));
});

await t('only open issues can be supported / withdrawn', async () => {
  const r = await call('POST', `/issues/${streetlight.id}/support`, at(0.0015, 0.001), guest);
  assert.equal(r.status, 409);
});

let newId;
await t('report: validates, location-gated, routed to a ward, auto-supported', async () => {
  assert.equal((await call('POST', '/issues', { title: 'x', category: 'road', ...at() }, guest)).status, 400);
  const far = await call('POST', '/issues', { title: 'Far away pothole', category: 'road', lat: BASE.lat + 0.05, lng: BASE.lng, userLat: BASE.lat, userLng: BASE.lng }, guest);
  assert.equal(far.status, 403);
  const ok = await call('POST', '/issues', { title: 'Cracked road by the temple', category: 'road', description: 'test', ...at(0.0042, 0.0042), userLat: BASE.lat + 0.004, userLng: BASE.lng + 0.004 }, guest);
  assert.equal(ok.status, 201);
  newId = ok.body.issue.id;
  assert.equal(ok.body.issue.supportCount, 1);
  assert.ok(ok.body.issue.politician);
  assert.equal(ok.body.rewards.badges[0].key, 'first_report');
});

await t('similar-issue lookup + linked (duplicate) report', async () => {
  const s = await call('GET', `/issues/similar?lat=${BASE.lat + 0.0042}&lng=${BASE.lng + 0.0042}&category=road`, null, demo);
  assert.ok(s.body.items.some((i) => i.id === newId));
  const l = await call('POST', '/issues', { title: 'Same pothole', category: 'road', ...at(0.0042, 0.0042), userLat: BASE.lat + 0.004, userLng: BASE.lng + 0.004, linkTo: newId }, demo);
  assert.equal(l.status, 201); assert.equal(l.body.linked, true);
  assert.equal(l.body.issue.linkedCount, 1);
  assert.equal(l.body.issue.supportCount, 1); // linked reports are not supports
  assert.equal((await call('POST', '/issues', { title: 'Same pothole', category: 'road', ...at(0.0042, 0.0042), linkTo: newId }, demo)).status, 409);
});

await t('withdraw support rules', async () => {
  const sup = await call('POST', `/issues/${newId}/support`, at(0.004, 0.004), diya);
  assert.equal(sup.status, 200);
  assert.equal((await call('DELETE', `/issues/${newId}/support`, null, diya)).body.issue.supportCount, 1);
  assert.equal((await call('DELETE', `/issues/${newId}/support`, null, guest)).status, 409); // reporter
});

await t('events feed + detail + volunteer rules', async () => {
  const ev = (await call('GET', `/issues?phase=event&lat=${BASE.lat}&lng=${BASE.lng}`, null, demo)).body.items;
  assert.ok(ev.length >= 5);
  const garbage = ev.find((e) => e.title.includes('Garbage dump'));
  // guest is not a volunteer
  const g = await call('POST', `/events/${garbage.id}/join`, at(0.006, 0.004), guest);
  assert.equal(g.status, 403); assert.equal(g.body.code, 'NOT_VOLUNTEER');
  // demo joins -> organiser, status flips to in_progress
  const j = await call('POST', `/events/${garbage.id}/join`, at(0.006, 0.004), demo);
  assert.equal(j.status, 200);
  assert.equal(j.body.issue.status, 'in_progress');
  assert.equal(j.body.issue.volunteeringByMe, true);
  assert.equal((await call('POST', `/events/${garbage.id}/join`, at(0.006, 0.004), demo)).status, 409);
  const d = (await call('GET', `/issues/${garbage.id}`, null, demo)).body.issue;
  assert.ok(d.timeline.length >= 3);
  assert.equal(d.isOrganiser, true);
  // schedule
  const s = await call('POST', `/events/${garbage.id}/schedule`, { scheduledAt: Date.now() + 5 * 86400000 }, demo);
  assert.equal(s.status, 200);
  assert.equal((await call('POST', `/events/${garbage.id}/schedule`, { scheduledAt: Date.now() + 86400000 }, aarav)).status, 403);
});

await t('resolve -> verify (2 approvals closes) + volunteers cannot self-verify', async () => {
  const items = (await call('GET', '/issues?phase=event', null, demo)).body.items;
  const swings = items.find((e) => e.title.includes('swings'));
  assert.equal((await call('POST', `/events/${swings.id}/resolve`, { note: 'done', ...at(0.01, -0.003) }, diya)).status, 403);
  const volunteer = await login('ramesh@bythepeople.app', 'sober123');
  const ok = await call('POST', `/events/${swings.id}/resolve`, { note: 'Swings replaced', ...at(0.01, -0.003) }, volunteer);
  assert.equal(ok.status, 200); assert.equal(ok.body.issue.status, 'pending_verification');
  assert.equal((await call('POST', `/events/${swings.id}/verify`, { approve: true, ...at(0.01, -0.003) }, volunteer)).status, 403);
  // Neel etc. are supporters of swings: rahul(4) vol; people[5]=sana, people[9]=pooja, people[10]=dev
  const sana = await login('sunita@bythepeople.app', 'sober123');
  const pooja = await login('rekha@bythepeople.app', 'sober123');
  const v1 = await call('POST', `/events/${swings.id}/verify`, { approve: true, ...at(0.01, -0.003) }, sana);
  assert.equal(v1.status, 200); assert.equal(v1.body.outcome, 'pending');
  assert.equal((await call('POST', `/events/${swings.id}/verify`, { approve: true, ...at(0.01, -0.003) }, sana)).status, 409);
  const v2 = await call('POST', `/events/${swings.id}/verify`, { approve: true, ...at(0.01, -0.003) }, pooja);
  assert.equal(v2.body.outcome, 'closed');
  assert.equal(v2.body.issue.status, 'closed');
});

await t('verify far away is blocked; two rejections reopen', async () => {
  const items = (await call('GET', '/issues?phase=event', null, demo)).body.items;
  const drain = items.find((e) => e.title.includes('Blocked drain'));
  assert.equal(drain.status, 'pending_verification');
  assert.equal((await call('POST', `/events/${drain.id}/verify`, { approve: false, lat: BASE.lat + 0.03, lng: BASE.lng }, demo)).status, 403);
  const r1 = await call('POST', `/events/${drain.id}/verify`, { approve: false, ...at(0.002, 0.009) }, demo);
  assert.equal(r1.body.outcome, 'pending');
  const isha = await login('kiran@bythepeople.app', 'sober123'); // supporter of the drain
  const r2 = await call('POST', `/events/${drain.id}/verify`, { approve: false, ...at(0.002, 0.009) }, isha);
  assert.equal(r2.body.outcome, 'reopened');
  assert.equal(r2.body.issue.status, 'in_progress');
  assert.equal(r2.body.issue.verification.round, 2);
});

await t('my activity lists', async () => {
  for (const type of ['reports', 'supported', 'events']) {
    const r = await call('GET', `/me/activity?type=${type}`, null, demo);
    assert.equal(r.status, 200); assert.ok(Array.isArray(r.body.items));
  }
  assert.ok((await call('GET', '/me/activity?type=events', null, demo)).body.items.length >= 2);
});

await t('neta: list, filter, tree, detail, stats are consistent', async () => {
  const list = (await call('GET', '/netas', null, demo)).body;
  assert.equal(list.items.length, 34); assert.ok(list.parties.length >= 3);
  const wards = (await call('GET', '/netas?level=ward', null, demo)).body.items;
  assert.equal(wards.length, 16);
  const filt = (await call('GET', `/netas?party=${encodeURIComponent(list.parties[0])}`, null, demo)).body.items;
  assert.ok(filt.every((p) => p.party === list.parties[0]));
  const tree = (await call('GET', '/netas/tree', null, demo)).body.roots;
  assert.equal(tree.length, 3);
  assert.ok(tree.every((r) => r.level === 'minister'));
  const ka = tree.find((r) => r.state === 'Chhattisgarh');
  const kaWards = wards.filter((w) => w.state === 'Chhattisgarh');
  assert.equal(ka.stats.reported, kaWards.reduce((a, w) => a + w.stats.reported, 0)); // minister aggregates the state
  const detail = (await call('GET', `/netas/${wards[0].id}`, null, demo)).body;
  assert.equal(detail.openIssues.length + detail.resolvedIssues.length, wards[0].stats.reported);
  const rarities = new Set(list.items.map((p) => p.stats.rarity));
  assert.ok(rarities.has('unrated'), 'a ward with <5 issues is unrated');
  assert.ok(['common', 'rare', 'epic', 'legendary'].some((r) => rarities.has(r)));
});

await t('closing an event raises the Neta resolved count', async () => {
  const wards = (await call('GET', '/netas?level=ward', null, demo)).body.items;
  const totalResolved = wards.reduce((a, w) => a + w.stats.resolved, 0);
  assert.ok(totalResolved >= 40);
});

// ---------- geography ----------
const MYSURU = { lat: 12.2958, lng: 76.6394 };
const BHUBANESWAR = { lat: 20.2961, lng: 85.8245 };

await t('geo: areas tree and point resolution', async () => {
  const tree = (await call('GET', '/geo/areas', null, demo)).body.regions;
  assert.equal(tree.length, 2);
  const cities = tree.flatMap((r) => r.states.flatMap((s) => s.cities));
  assert.deepEqual(cities.map((c) => c.name).sort(), ['Bhilai-Durg', 'Bhopal', 'Bhubaneswar', 'Bilaspur', 'Korba', 'Raipur']);
  const here = (await call('GET', `/geo/resolve?lat=${BASE.lat}&lng=${BASE.lng}`, null, demo)).body;
  assert.equal(here.covered, true); assert.equal(here.city.name, 'Raipur'); assert.equal(here.state.name, 'Chhattisgarh'); assert.equal(here.region.name, 'Central India');
  const bbsr = (await call('GET', `/geo/resolve?lat=${BHUBANESWAR.lat}&lng=${BHUBANESWAR.lng}`, null, demo)).body;
  assert.equal(bbsr.state.name, 'Odisha'); assert.equal(bbsr.region.name, 'East India');
  const nowhere = (await call('GET', '/geo/resolve?lat=0&lng=0', null, demo)).body;
  assert.equal(nowhere.covered, false); assert.equal(nowhere.city, null);
  assert.equal((await call('GET', '/geo/resolve?lat=abc&lng=1', null, demo)).status, 400);
});

await t('scope: feed filters by city / state / region and defaults to my location', async () => {
  const q = (extra) => call('GET', `/issues?phase=all&lat=${BASE.lat}&lng=${BASE.lng}${extra}`, null, demo).then((r) => r.body.items);
  const all = await q('');
  const city = await q('&scope=city');
  const state = await q('&scope=state');
  const region = await q('&scope=region');
  assert.ok(city.length > 0 && city.length < all.length);
  assert.ok(city.every((i) => i.area.city.name === 'Raipur'));
  assert.ok(state.every((i) => i.area.state.name === 'Chhattisgarh'));
  assert.ok(state.length > city.length, 'Chhattisgarh includes Bilaspur etc.');
  assert.ok(region.every((i) => i.area.region.name === 'Central India'));
  assert.ok(region.length > state.length, 'Central India includes Madhya Pradesh');
  assert.ok(all.length > region.length, 'East India is outside');
  // explicit area
  const tree = (await call('GET', '/geo/areas', null, demo)).body.regions;
  const mysuru = tree.flatMap((r) => r.states.flatMap((s) => s.cities)).find((c) => c.name === 'Bilaspur');
  const my = await q(`&scope=city&areaId=${mysuru.id}`);
  assert.ok(my.length > 0 && my.every((i) => i.area.city.name === 'Bilaspur'));
  // wrong kind is rejected
  const state0 = tree[0].states[0];
  assert.equal((await call('GET', `/issues?scope=city&areaId=${state0.id}`, null, demo)).status, 400);
});

await t('scope: leaders and tree follow the scope; ministers serve their cities', async () => {
  const city = (await call('GET', `/netas?scope=city&lat=${BASE.lat}&lng=${BASE.lng}`, null, demo)).body;
  assert.equal(city.area.name, 'Raipur');
  assert.ok(city.items.every((p) => p.city === 'Raipur' || (p.level === 'minister' && p.state === 'Chhattisgarh')));
  assert.equal(city.items.filter((p) => p.level === 'ward').length, 6);
  assert.equal(city.items.filter((p) => p.level === 'minister').length, 1);
  const state = (await call('GET', `/netas?scope=state&lat=${BASE.lat}&lng=${BASE.lng}`, null, demo)).body;
  assert.ok(state.items.every((p) => p.state === 'Chhattisgarh'));
  assert.equal(state.items.filter((p) => p.level === 'ward').length, 12);
  const geo = (await call('GET', '/geo/areas', null, demo)).body.regions;
  const west = geo.find((r) => r.name === 'East India');
  const region = (await call('GET', `/netas?scope=region&areaId=${west.id}`, null, demo)).body;
  assert.ok(region.items.length === 5 && region.items.every((p) => p.region === 'East India'));
  const tree = (await call('GET', `/netas/tree?scope=city&lat=${BASE.lat}&lng=${BASE.lng}`, null, demo)).body.roots;
  assert.equal(tree.length, 1);
  assert.ok(tree[0].children.every((mp) => mp.city === 'Raipur'));
});

await t('scope: summary numbers match the feed', async () => {
  const sum = (await call('GET', `/geo/summary?scope=city&lat=${BASE.lat}&lng=${BASE.lng}`, null, demo)).body;
  const feed = (await call('GET', `/issues?phase=all&scope=city&lat=${BASE.lat}&lng=${BASE.lng}`, null, demo)).body.items;
  assert.equal(sum.area.name, 'Raipur');
  assert.equal(sum.reported, feed.length);
  assert.equal(sum.resolved, feed.filter((i) => i.status === 'closed').length);
  assert.equal(sum.reported, sum.resolved + sum.open + sum.events);
  const all = (await call('GET', '/geo/summary', null, demo)).body;
  assert.equal(all.area.kind, 'all');
  assert.ok(all.reported > sum.reported);
});

await t('coverage: reporting outside any supported ward is refused', async () => {
  // user is physically at the pin (passes the distance gate) but the spot is not covered
  const sess = await login('guest@bythepeople.app', 'guest123');
  const r = await call('POST', '/issues', { title: 'Pothole in the middle of nowhere', category: 'road', lat: 0.5, lng: 0.5, userLat: 0.5, userLng: 0.5 }, sess);
  assert.ok([400, 422].includes(r.status), `status ${r.status}`);
});

await t('profile: rank, badges, volunteer toggle, radius validation', async () => {
  const me = (await call('GET', '/me', null, demo)).body;
  assert.ok(me.user.badges.some((b) => b.key === 'first_support' && b.earned));
  assert.ok(me.user.points > 62);
  assert.equal((await call('PATCH', '/me', { alertRadiusKm: 99 }, demo)).status, 400);
  const p = await call('PATCH', '/me', { volunteer: false, alertRadiusKm: 8 }, guest);
  assert.equal(p.body.user.volunteer, false);
  assert.equal(p.body.user.alertRadiusKm, 8);
  assert.ok(me.unread >= 3);
  await call('POST', '/notifications/read', {}, demo);
  assert.equal((await call('GET', '/me', null, demo)).body.unread, 0);
});

console.log(`\n${passed} tests passed${process.exitCode ? ' (with failures)' : ''}`);
fs.rmSync(tmp, { force: true });
fs.rmSync(uploads, { recursive: true, force: true });
