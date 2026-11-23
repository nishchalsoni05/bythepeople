import { db, tx } from './db.js';
import {
  CONFIG, CATEGORIES, RANKS, POINTS, BADGES, SEVERITY_WEIGHT, authorityFor,
} from './config.js';
import { now, DAY, haversineKm, ApiError, num } from './util.js';
import {
  parseJson, cleanMedia, publicUrl, userRef, userRefFromRow, likedBy,
} from './common.js';

// ---------- severity ----------
export function severityOf(supports, linked, createdAt, category) {
  const days = Math.min(30, (now() - createdAt) / DAY);
  const cat = CATEGORIES[category] || CATEGORIES.other;
  const score = 2 * supports + 1.5 * linked + 0.5 * days + cat.weight;
  let level = 'low';
  if (score >= 22) level = 'critical';
  else if (score >= 14) level = 'high';
  else if (score >= 8) level = 'medium';
  return { score: Math.round(score * 10) / 10, level };
}

// ---------- location ----------
export function parseLoc(lat, lng, label = 'location') {
  const la = num(lat);
  const ln = num(lng);
  if (!Number.isFinite(la) || !Number.isFinite(ln) || Math.abs(la) > 90 || Math.abs(ln) > 180) {
    throw new ApiError(400, 'BAD_LOCATION', `A valid ${label} is required`);
  }
  return { lat: la, lng: ln };
}

// Records the user's latest position; rejects teleporting (spoof guard).
export function touchLocation(user, lat, lng, strict = true) {
  const { lat: la, lng: ln } = parseLoc(lat, lng, 'current location');
  const t = now();
  if (user.last_lat != null && user.last_ts && t - user.last_ts < 10 * 60 * 1000) {
    const km = haversineKm(user.last_lat, user.last_lng, la, ln);
    const hours = Math.max((t - user.last_ts) / 3600000, 1 / 3600);
    if (km > 5 && km / hours > CONFIG.maxSpeedKmh) {
      if (strict) {
        throw new ApiError(400, 'LOCATION_JUMP', 'Location changed implausibly fast. Please try again in a moment.');
      }
      return false;
    }
  }
  db.prepare('UPDATE users SET last_lat=?, last_lng=?, last_ts=? WHERE id=?').run(la, ln, t, user.id);
  user.last_lat = la; user.last_lng = ln; user.last_ts = t;
  return true;
}

export function requireWithin(user, lat, lng, issue, radiusKm) {
  const d = haversineKm(lat, lng, issue.lat, issue.lng);
  if (d > radiusKm) {
    throw new ApiError(403, 'OUT_OF_RANGE',
      `You are ${d.toFixed(1)} km away. You need to be within ${radiusKm} km of this issue.`,
      { distanceKm: round1(d), radiusKm });
  }
  return d;
}

export const round1 = (n) => Math.round(n * 10) / 10;
export const radiusFor = (category) => (CATEGORIES[category] || CATEGORIES.other).radiusKm;

// ---------- rank / points / badges ----------
export function rankFor(points) {
  let idx = 0;
  RANKS.forEach((r, i) => { if (points >= r.min) idx = i; });
  const cur = RANKS[idx];
  const next = RANKS[idx + 1] || null;
  return {
    name: cur.name, index: idx, min: cur.min,
    next: next ? next.name : null,
    nextAt: next ? next.min : null,
    progress: next ? (points - cur.min) / (next.min - cur.min) : 1,
  };
}

// Servings of food a user has given (as donor) or taken on (as a claiming foundation/volunteer).
export function mealsFor(userId) {
  return db.prepare(`SELECT COALESCE(SUM(servings),0) c FROM donations
    WHERE kind='food' AND status IN ('claimed','picked_up','distributed') AND (donor_id=? OR claimed_by=?)`).get(userId, userId).c;
}

function badgeStats(userId) {
  const one = (sql, ...p) => db.prepare(sql).get(...p).c;
  return {
    reports: one('SELECT COUNT(*) c FROM issues WHERE reporter_id=?', userId),
    supports: one('SELECT COUNT(*) c FROM supports WHERE user_id=?', userId),
    sparks: one("SELECT COUNT(*) c FROM issues WHERE reporter_id=? AND event_at IS NOT NULL", userId),
    joins: one('SELECT COUNT(*) c FROM volunteers WHERE user_id=?', userId),
    verifies: one('SELECT COUNT(*) c FROM verifications WHERE user_id=?', userId),
    closedHelped: one(
      "SELECT COUNT(*) c FROM volunteers v JOIN issues i ON i.id=v.issue_id WHERE v.user_id=? AND i.status='closed'", userId),
    points: one('SELECT points c FROM users WHERE id=?', userId),
    checkins: one('SELECT COUNT(*) c FROM gathering_rsvps WHERE user_id=? AND checked_in_at IS NOT NULL', userId),
    greenCheckins: one(
      `SELECT COUNT(*) c FROM gathering_rsvps r JOIN gatherings g ON g.id=r.gathering_id
       WHERE r.user_id=? AND r.checked_in_at IS NOT NULL AND g.type IN ('plantation','cleanup')`, userId),
    donated: one("SELECT COUNT(*) c FROM donations WHERE donor_id=? AND status='distributed'", userId),
    foodDonated: one("SELECT COUNT(*) c FROM donations WHERE donor_id=? AND status='distributed' AND kind='food'", userId),
    comments: one('SELECT COUNT(*) c FROM comments WHERE user_id=?', userId),
    meals: mealsFor(userId),
  };
}

const BADGE_RULES = {
  first_report: (s) => s.reports >= 1,
  first_support: (s) => s.supports >= 1,
  watchdog: (s) => s.supports >= 5,
  town_crier: (s) => s.reports >= 5,
  spark: (s) => s.sparks >= 1,
  first_responder: (s) => s.joins >= 1,
  truth_seeker: (s) => s.verifies >= 3,
  hero: (s) => s.closedHelped >= 1,
  best_citizen: (s) => s.points >= 300,
  volunteer_heart: (s) => s.checkins >= 1,
  green_thumb: (s) => s.greenCheckins >= 3,
  giver: (s) => s.donated >= 1,
  feeder: (s) => s.foodDonated >= 5,
  voice: (s) => s.comments >= 5,
};

// Adds points, evaluates badges, returns a "rewards" payload for celebration UI.
export function award(userId, pts, reasons = []) {
  const before = db.prepare('SELECT points FROM users WHERE id=?').get(userId).points;
  if (pts) db.prepare('UPDATE users SET points = points + ? WHERE id=?').run(pts, userId);
  const after = before + pts;
  const stats = badgeStats(userId);
  const have = new Set(db.prepare('SELECT badge_key FROM user_badges WHERE user_id=?').all(userId).map((r) => r.badge_key));
  const newBadges = [];
  for (const b of BADGES) {
    if (!have.has(b.key) && BADGE_RULES[b.key](stats)) {
      db.prepare('INSERT INTO user_badges (user_id, badge_key, earned_at) VALUES (?,?,?)').run(userId, b.key, now());
      newBadges.push(b);
    }
  }
  const rb = rankFor(before);
  const ra = rankFor(after);
  return {
    points: pts, total: after, reasons,
    badges: newBadges,
    rankUp: ra.index > rb.index ? { from: rb.name, to: ra.name } : null,
  };
}

export function mergeRewards(a, b) {
  if (!a) return b;
  if (!b) return a;
  return {
    points: a.points + b.points, total: Math.max(a.total, b.total),
    reasons: [...a.reasons, ...b.reasons],
    badges: [...a.badges, ...b.badges],
    rankUp: a.rankUp || b.rankUp,
  };
}

// ---------- notifications ----------
export function notify(userId, type, title, body, issueId = null, refType = null, refId = null) {
  if (issueId != null && refType == null) { refType = 'issue'; refId = issueId; }
  db.prepare('INSERT INTO notifications (user_id,type,title,body,issue_id,read,created_at,ref_type,ref_id) VALUES (?,?,?,?,?,0,?,?,?)')
    .run(userId, type, title, body, issueId, now(), refType, refId);
}

/** Timeline entry. kind: status | authority | neta | system (system when nobody acted). */
export function addHistory(issueId, status, note, userId = null, extra = {}) {
  const actor = userId ? db.prepare('SELECT role FROM users WHERE id=?').get(userId) : null;
  const kind = extra.kind || (userId ? 'status' : 'system');
  db.prepare('INSERT INTO status_history (issue_id,status,note,user_id,created_at,media,actor_role,kind) VALUES (?,?,?,?,?,?,?,?)')
    .run(issueId, status, note, userId, now(), JSON.stringify(extra.media || []), actor?.role || null, kind);
}

// ---------- geography ----------
const areaById = (id) => (id == null ? null : db.prepare('SELECT * FROM areas WHERE id=?').get(id));

/** ward -> { ward, city, state, region } (area rows). */
export function chainFromWard(ward) {
  const city = areaById(ward.parent_id);
  const state = areaById(city.parent_id);
  const region = areaById(state.parent_id);
  return { ward, city, state, region };
}

/** Nearest ward whose radius contains the point, or null when By the People does not cover it. */
export function wardAt(lat, lng) {
  const wards = db.prepare("SELECT * FROM areas WHERE kind='ward'").all();
  let best = null;
  let bestD = Infinity;
  for (const w of wards) {
    const d = haversineKm(lat, lng, w.lat, w.lng);
    if (d <= w.radius_km && d < bestD) { best = w; bestD = d; }
  }
  return best;
}

/** Issue routing: ward -> its councillor. Null when the spot is outside every covered ward. */
export function routeIssue(lat, lng) {
  const ward = wardAt(lat, lng);
  if (!ward) return null;
  const politician = db.prepare("SELECT * FROM politicians WHERE level='ward' AND area_id=?").get(ward.id);
  if (!politician) return null;
  return { politician, chain: chainFromWard(ward) };
}

const brief = (a) => (a ? { id: a.id, name: a.name } : null);

/**
 * Where is this point? Falls back from ward to city so users between wards
 * still get a city/state/region (needed for default feed scope).
 */
export function resolveArea(lat, lng) {
  const ward = wardAt(lat, lng);
  if (ward) {
    const c = chainFromWard(ward);
    return { covered: true, ward: brief(c.ward), city: brief(c.city), state: brief(c.state), region: brief(c.region), defaultScope: 'city', label: c.ward.name, nearestCity: null, distanceKm: 0 };
  }
  const cities = db.prepare("SELECT * FROM areas WHERE kind='city'").all();
  let best = null;
  let bestD = Infinity;
  for (const c of cities) {
    const d = haversineKm(lat, lng, c.lat, c.lng);
    if (d <= c.radius_km && d < bestD) { best = c; bestD = d; }
  }
  if (best) {
    const state = areaById(best.parent_id);
    const region = areaById(state.parent_id);
    return { covered: true, ward: null, city: brief(best), state: brief(state), region: brief(region), defaultScope: 'city', label: best.name, nearestCity: null, distanceKm: 0 };
  }
  // Outside every city/ward: never an empty state. Fall back to the state of the nearest city
  // (e.g. a town 45 km from Raipur gets "Chhattisgarh"), or to everywhere if nothing is near.
  let near = null;
  let nearD = Infinity;
  for (const c of cities) {
    const d = haversineKm(lat, lng, c.lat, c.lng);
    if (d < nearD) { near = c; nearD = d; }
  }
  const dist = near ? Math.round(nearD * 10) / 10 : null;
  if (near && nearD <= CONFIG.stateFallbackKm) {
    const state = areaById(near.parent_id);
    const region = areaById(state.parent_id);
    return { covered: false, ward: null, city: null, state: brief(state), region: brief(region), defaultScope: 'state', label: state.name, nearestCity: brief(near), distanceKm: dist };
  }
  return { covered: false, ward: null, city: null, state: null, region: null, defaultScope: 'all', label: 'All regions', nearestCity: near ? brief(near) : null, distanceKm: dist };
}

/**
 * Parses ?scope=city|state|region|all&areaId=. When areaId is missing it is derived from
 * the caller's location so every level defaults to "where I am".
 */
export function resolveScope(query, user, loc = null) {
  const scope = ['city', 'state', 'region'].includes(query.scope) ? query.scope : 'all';
  if (scope === 'all') return { scope: 'all', area: null };
  let area = null;
  const wanted = Number(query.areaId);
  if (Number.isFinite(wanted) && wanted > 0) {
    area = areaById(wanted);
    if (!area || area.kind !== scope) throw new ApiError(400, 'BAD_SCOPE', `areaId is not a ${scope}`);
  } else {
    const at = loc || (user.last_lat != null ? { lat: user.last_lat, lng: user.last_lng } : user.home_lat != null ? { lat: user.home_lat, lng: user.home_lng } : null);
    const r = at ? resolveArea(at.lat, at.lng) : null;
    const hit = r && r[scope];
    area = hit ? areaById(hit.id) : null;
    if (!area) {
      // Client is outside coverage for the requested level: widen (city -> state -> region -> all)
      // instead of returning an empty feed.
      const order = ['city', 'state', 'region'];
      for (const wider of order.slice(order.indexOf(scope) + 1)) {
        const h = r && r[wider];
        if (h) return { scope: wider, area: areaById(h.id), requested: scope };
      }
      return { scope: 'all', area: null, requested: scope };
    }
  }
  return { scope, area };
}

const SCOPE_COLUMN = { city: 'city_id', state: 'state_id', region: 'region_id' };

/** SQL fragment + params restricting issues to a scope. */
export function scopeSql({ scope, area }, alias = 'i') {
  if (scope === 'all' || !area) return { sql: '', params: [] };
  return { sql: `${alias}.${SCOPE_COLUMN[scope]} = ?`, params: [area.id] };
}

/** Does a leader serve the scope? A state minister serves every city in their state. */
export function leaderInScope(p, { scope, area }) {
  if (scope === 'all' || !area) return true;
  if (scope === 'city') return p.city_id === area.id || (p.level === 'minister' && p.state_id === area.parent_id);
  if (scope === 'state') return p.state_id === area.id;
  return p.region_id === area.id;
}

export function areaTree() {
  const all = db.prepare('SELECT * FROM areas ORDER BY id').all();
  const kids = (id) => all.filter((a) => a.parent_id === id);
  return all.filter((a) => a.kind === 'region').map((r) => ({
    id: r.id, name: r.name,
    states: kids(r.id).map((s) => ({
      id: s.id, name: s.name,
      cities: kids(s.id).map((c) => ({
        id: c.id, name: c.name, lat: c.lat, lng: c.lng,
        wards: kids(c.id).map((w) => ({ id: w.id, name: w.name })),
      })),
    })),
  }));
}

/** Headline numbers for a scope (shown above the Neta cards). */
export function scopeSummary(sc) {
  const w = scopeSql(sc);
  const where = w.sql ? `WHERE ${w.sql}` : '';
  const rows = db.prepare(`SELECT i.status, i.created_at, i.closed_at FROM issues i ${where}`).all(...w.params);
  let resolved = 0, events = 0, open = 0, days = 0;
  for (const r of rows) {
    if (r.status === 'closed') { resolved++; days += (r.closed_at - r.created_at) / DAY; }
    else if (r.status === 'open') open++;
    else events++;
  }
  const reported = rows.length;
  return {
    scope: sc.scope,
    area: sc.area ? { id: sc.area.id, name: sc.area.name, kind: sc.area.kind } : { id: null, name: 'Everywhere', kind: 'all' },
    reported, resolved, open, events,
    rate: reported >= CONFIG.minNetaSample ? Math.round((resolved / reported) * 1000) / 1000 : null,
    avgDaysToResolve: resolved ? Math.round((days / resolved) * 10) / 10 : null,
  };
}

// ---------- issue reading ----------
const ISSUE_SQL = `
SELECT i.*,
  (SELECT COUNT(*) FROM supports s WHERE s.issue_id=i.id) AS support_count,
  (SELECT COUNT(*) FROM linked_reports l WHERE l.issue_id=i.id) AS linked_count,
  (SELECT COUNT(*) FROM volunteers v WHERE v.issue_id=i.id) AS volunteer_count,
  (SELECT COUNT(*) FROM likes lk WHERE lk.target_type='issue' AND lk.target_id=i.id) AS like_count,
  (SELECT COUNT(*) FROM comments cm WHERE cm.target_type='issue' AND cm.target_id=i.id) AS comment_count,
  u.name AS reporter_name, u.hue AS reporter_hue, u.role AS reporter_role,
  u.org_name AS reporter_org, u.verified AS reporter_verified,
  p.name AS pol_name, p.party AS pol_party, p.constituency AS pol_constituency, p.level AS pol_level, p.hue AS pol_hue,
  aw.name AS ward_name, ac.name AS city_name, ast.name AS state_name, ar.name AS region_name
FROM issues i
JOIN users u ON u.id=i.reporter_id
LEFT JOIN politicians p ON p.id=i.politician_id
LEFT JOIN areas aw ON aw.id=i.ward_id
LEFT JOIN areas ac ON ac.id=i.city_id
LEFT JOIN areas ast ON ast.id=i.state_id
LEFT JOIN areas ar ON ar.id=i.region_id`;

export function issueRows(where = '', ...params) {
  return db.prepare(`${ISSUE_SQL} ${where}`).all(...params);
}

export function issueRow(id) {
  return db.prepare(`${ISSUE_SQL} WHERE i.id=?`).get(id);
}

const avatarsFor = (table, issueId, limit = 5) =>
  db.prepare(`SELECT u.id, u.name, u.hue FROM ${table} t JOIN users u ON u.id=t.user_id
              WHERE t.issue_id=? ORDER BY ${table === 'supports' ? 't.created_at' : 't.joined_at'} LIMIT ?`)
    .all(issueId, limit);

export function phaseOf(status) {
  if (status === 'open') return 'issue';
  if (status === 'closed') return 'closed';
  return 'event';
}

export function timelineFor(issueId) {
  return db.prepare(`SELECT h.id, h.status, h.note, h.created_at, h.media, h.actor_role, h.kind, u.name AS user_name
      FROM status_history h LEFT JOIN users u ON u.id=h.user_id WHERE h.issue_id=? ORDER BY h.created_at, h.id`).all(issueId)
    .map((h) => ({
      id: h.id, status: h.status, note: h.note, createdAt: h.created_at, userName: h.user_name,
      media: parseJson(h.media, []), actorRole: h.actor_role, kind: h.kind || 'status',
    }));
}

const AUTH_LABEL = { open: 'Open', acknowledged: 'Acknowledged', in_progress: 'In progress', resolved: 'Resolved' };

export const authorityStatusOf = (r) => (r.status === 'closed' ? 'resolved' : r.authority_status || 'open');

export function issueShareText(r) {
  const a = authorityFor(r.city_name, r.category);
  const st = AUTH_LABEL[authorityStatusOf(r)];
  return `${r.title} in ${r.city_name || 'our city'}. Status: ${st}. ${a.handle} please act on this. `
    + `${r.support_count} neighbours support it. Track it: ${publicUrl('issue', r.id)}`;
}

function socialFields(r) {
  const supports = r.support_count;
  return {
    likeCount: r.like_count, commentCount: r.comment_count, shareCount: r.share_count,
    engagement: r.like_count + 2 * supports + r.comment_count + r.share_count,
    media: parseJson(r.media, []),
    authority: authorityFor(r.city_name, r.category),
    authorityStatus: authorityStatusOf(r),
    assignedTo: r.assigned_to || null,
    escalated: !!r.escalated,
    escalatedBy: r.escalated ? userRef(r.escalated_by) : null,
    escalationNote: r.escalated ? r.escalation_note || '' : null,
    shareText: issueShareText(r),
    publicUrl: publicUrl('issue', r.id),
  };
}

export function issueView(r, user, loc = null, detail = false) {
  const sev = severityOf(r.support_count, r.linked_count, r.created_at, r.category);
  const cat = CATEGORIES[r.category] || CATEGORIES.other;
  const view = {
    id: r.id, title: r.title, description: r.description, category: r.category,
    categoryLabel: cat.label, radiusKm: cat.radiusKm,
    lat: r.lat, lng: r.lng, address: r.address,
    status: r.status, phase: phaseOf(r.status),
    severity: sev.level, severityScore: sev.score,
    supportCount: r.support_count, linkedCount: r.linked_count,
    volunteerCount: r.volunteer_count,
    threshold: CONFIG.eventThreshold,
    createdAt: r.created_at, eventAt: r.event_at, scheduledAt: r.scheduled_at,
    resolvedAt: r.resolved_at, closedAt: r.closed_at, resolutionNote: r.resolution_note,
    reporter: userRefFromRow({
      id: r.reporter_id, name: r.reporter_name, hue: r.reporter_hue, role: r.reporter_role,
      org_name: r.reporter_org, verified: r.reporter_verified,
    }),
    politician: r.politician_id ? {
      id: r.politician_id, name: r.pol_name, party: r.pol_party,
      constituency: r.pol_constituency, level: r.pol_level, hue: r.pol_hue,
    } : null,
    area: {
      ward: r.ward_id ? { id: r.ward_id, name: r.ward_name } : null,
      city: r.city_id ? { id: r.city_id, name: r.city_name } : null,
      state: r.state_id ? { id: r.state_id, name: r.state_name } : null,
      region: r.region_id ? { id: r.region_id, name: r.region_name } : null,
    },
    supporters: avatarsFor('supports', r.id),
    volunteers: avatarsFor('volunteers', r.id),
    ...socialFields(r),
  };
  if (loc) {
    view.distanceKm = round1(haversineKm(loc.lat, loc.lng, r.lat, r.lng));
    view.inRange = view.distanceKm <= cat.radiusKm;
  }
  if (user) {
    view.supportedByMe = !!db.prepare('SELECT 1 x FROM supports WHERE issue_id=? AND user_id=?').get(r.id, user.id);
    view.volunteeringByMe = !!db.prepare('SELECT 1 x FROM volunteers WHERE issue_id=? AND user_id=?').get(r.id, user.id);
    view.reportedByMe = r.reporter_id === user.id;
    view.likedByMe = likedBy('issue', r.id, user);
  } else view.likedByMe = false;
  if (detail) {
    view.timeline = timelineFor(r.id);
    view.supporters = avatarsFor('supports', r.id, 50);
    view.volunteers = avatarsFor('volunteers', r.id, 50);
    const v = db.prepare('SELECT approve, COUNT(*) c FROM verifications WHERE issue_id=? AND round=? GROUP BY approve').all(r.id, r.round);
    view.verification = {
      needed: CONFIG.verifyNeeded,
      approvals: v.find((x) => x.approve === 1)?.c || 0,
      rejections: v.find((x) => x.approve === 0)?.c || 0,
      round: r.round,
    };
    if (user) {
      view.verifiedByMe = !!db.prepare('SELECT 1 x FROM verifications WHERE issue_id=? AND user_id=? AND round=?').get(r.id, user.id, r.round);
      view.isOrganiser = !!db.prepare("SELECT 1 x FROM volunteers WHERE issue_id=? AND user_id=? AND role='organiser'").get(r.id, user.id);
    }
  }
  return view;
}

// ---------- core actions ----------
export function convertToEvent(issue) {
  const t = now();
  const sched = new Date(t + CONFIG.scheduleDefaultDays * DAY);
  sched.setHours(10, 0, 0, 0);
  db.prepare("UPDATE issues SET status='event', event_at=?, scheduled_at=? WHERE id=?").run(t, sched.getTime(), issue.id);
  addHistory(issue.id, 'event', `Reached ${CONFIG.eventThreshold} supporters and became an event`);
  const notified = new Set();
  // volunteers within their alert radius
  const vols = db.prepare('SELECT * FROM users WHERE volunteer=1').all();
  for (const v of vols) {
    const la = v.last_lat ?? v.home_lat;
    const ln = v.last_lng ?? v.home_lng;
    if (la == null) continue;
    if (haversineKm(la, ln, issue.lat, issue.lng) <= v.alert_radius_km) {
      notify(v.id, 'event_nearby', 'New event near you', `"${issue.title}" needs volunteers`, issue.id);
      notified.add(v.id);
    }
  }
  const sups = db.prepare('SELECT user_id FROM supports WHERE issue_id=?').all(issue.id);
  for (const s of sups) {
    if (notified.has(s.user_id)) continue;
    notify(s.user_id, 'event_created', 'Your issue is now an event', `"${issue.title}" reached ${CONFIG.eventThreshold} supporters`, issue.id);
  }
  return award(issue.reporter_id, POINTS.eventCreated, ['Your report became an event']);
}

export function createIssue(user, body) {
  const title = String(body.title || '').trim();
  if (title.length < 4) throw new ApiError(400, 'BAD_TITLE', 'Please give the issue a short title (4+ characters)');
  const category = CATEGORIES[body.category] ? body.category : null;
  if (!category) throw new ApiError(400, 'BAD_CATEGORY', 'Pick a category');
  const pin = parseLoc(body.lat, body.lng, 'issue location');
  const media = cleanMedia(body.media);
  if (user.role === 'admin') {
    throw new ApiError(403, 'FORBIDDEN', 'Authority accounts resolve issues instead of reporting them. Use a citizen account to report.');
  }
  const me = parseLoc(body.userLat ?? body.lat, body.userLng ?? body.lng, 'current location');
  touchLocation(user, me.lat, me.lng);
  const radius = radiusFor(category);
  const d = haversineKm(me.lat, me.lng, pin.lat, pin.lng);
  if (d > radius && user.role !== 'neta') {
    throw new ApiError(403, 'OUT_OF_RANGE',
      `The pin is ${d.toFixed(1)} km from you. You can only report within ${radius} km.`,
      { distanceKm: round1(d), radiusKm: radius });
  }
  return tx(() => {
    // linking a duplicate instead of a new issue
    if (body.linkTo) {
      const target = issueRow(Number(body.linkTo));
      if (!target) throw new ApiError(404, 'NOT_FOUND', 'Issue not found');
      if (target.status === 'closed') throw new ApiError(409, 'CLOSED', 'That issue is already closed');
      requireWithin(user, me.lat, me.lng, target, radiusFor(target.category));
      const dup = db.prepare('SELECT 1 x FROM linked_reports WHERE issue_id=? AND user_id=?').get(target.id, user.id);
      const sup = db.prepare('SELECT 1 x FROM supports WHERE issue_id=? AND user_id=?').get(target.id, user.id);
      if (dup || sup || target.reporter_id === user.id) throw new ApiError(409, 'ALREADY', 'You are already part of this issue');
      db.prepare('INSERT INTO linked_reports (issue_id,user_id,note,created_at) VALUES (?,?,?,?)')
        .run(target.id, user.id, String(body.description || ''), now());
      addHistory(target.id, target.status, 'Another resident filed a matching report', user.id);
      const rewards = award(user.id, POINTS.report, ['Report filed']);
      return { issue: issueView(issueRow(target.id), user, me), linked: true, rewards };
    }
    const route = routeIssue(pin.lat, pin.lng);
    if (!route) {
      throw new ApiError(422, 'OUT_OF_COVERAGE', 'By the People does not cover this spot yet. Pick a location inside a supported city.');
    }
    const pol = route.politician;
    const ch = route.chain;
    const info = db.prepare(`INSERT INTO issues (title,description,category,lat,lng,address,reporter_id,politician_id,ward_id,city_id,state_id,region_id,status,created_at,media)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?, 'open', ?, ?)`)
      .run(title, String(body.description || '').trim(), category, pin.lat, pin.lng,
        body.address ? String(body.address) : null, user.id, pol.id, ch.ward.id, ch.city.id, ch.state.id, ch.region.id, now(),
        JSON.stringify(media));
    const id = Number(info.lastInsertRowid);
    db.prepare('INSERT INTO supports (issue_id,user_id,created_at) VALUES (?,?,?)').run(id, user.id, now());
    addHistory(id, 'open', 'Issue reported', user.id);
    notify(user.id, 'routed', 'Routed to your representative', `${pol.name} (${pol.constituency}, ${ch.city.name}) is responsible`, id);
    const rewards = award(user.id, POINTS.report, ['Report filed']);
    return { issue: issueView(issueRow(id), user, me), linked: false, rewards };
  });
}

export function supportIssue(user, id, body) {
  const me = parseLoc(body.lat, body.lng, 'current location');
  touchLocation(user, me.lat, me.lng);
  return tx(() => {
    const issue = issueRow(id);
    if (!issue) throw new ApiError(404, 'NOT_FOUND', 'Issue not found');
    if (issue.status !== 'open') throw new ApiError(409, 'NOT_OPEN', 'Only open issues can be supported');
    requireWithin(user, me.lat, me.lng, issue, radiusFor(issue.category));
    const exists = db.prepare('SELECT 1 x FROM supports WHERE issue_id=? AND user_id=?').get(id, user.id);
    if (exists) throw new ApiError(409, 'ALREADY', 'You already support this issue');
    db.prepare('INSERT INTO supports (issue_id,user_id,created_at) VALUES (?,?,?)').run(id, user.id, now());
    let rewards = award(user.id, POINTS.support, ['Supported an issue']);
    const count = db.prepare('SELECT COUNT(*) c FROM supports WHERE issue_id=?').get(id).c;
    let converted = false;
    if (count >= CONFIG.eventThreshold) {
      const r = convertToEvent(issue);
      converted = true;
      if (issue.reporter_id === user.id) rewards = mergeRewards(rewards, r);
    }
    return { issue: issueView(issueRow(id), user, me), converted, rewards };
  });
}

export function withdrawSupport(user, id) {
  return tx(() => {
    const issue = issueRow(id);
    if (!issue) throw new ApiError(404, 'NOT_FOUND', 'Issue not found');
    if (issue.status !== 'open') throw new ApiError(409, 'NOT_OPEN', 'Support can only be withdrawn before it becomes an event');
    if (issue.reporter_id === user.id) throw new ApiError(409, 'REPORTER', 'The reporter cannot withdraw support');
    const r = db.prepare('DELETE FROM supports WHERE issue_id=? AND user_id=?').run(id, user.id);
    if (!r.changes) throw new ApiError(409, 'NOT_SUPPORTING', 'You are not supporting this issue');
    return { issue: issueView(issueRow(id), user) };
  });
}

function eventOrThrow(id, statuses) {
  const issue = issueRow(id);
  if (!issue) throw new ApiError(404, 'NOT_FOUND', 'Event not found');
  if (!statuses.includes(issue.status)) {
    throw new ApiError(409, 'BAD_STATE', `This is ${issue.status === 'open' ? 'still an issue' : issue.status.replace('_', ' ')}`);
  }
  return issue;
}

export function joinEvent(user, id, body) {
  const me = parseLoc(body.lat, body.lng, 'current location');
  touchLocation(user, me.lat, me.lng);
  return tx(() => {
    const issue = eventOrThrow(id, ['event', 'in_progress']);
    if (!user.volunteer) throw new ApiError(403, 'NOT_VOLUNTEER', 'Turn on Volunteer mode in your profile to join events');
    const d = haversineKm(me.lat, me.lng, issue.lat, issue.lng);
    if (d > user.alert_radius_km) {
      throw new ApiError(403, 'OUT_OF_RANGE', `This event is ${d.toFixed(1)} km away, beyond your ${user.alert_radius_km} km volunteer radius.`,
        { distanceKm: round1(d), radiusKm: user.alert_radius_km });
    }
    if (db.prepare('SELECT 1 x FROM volunteers WHERE issue_id=? AND user_id=?').get(id, user.id)) {
      throw new ApiError(409, 'ALREADY', 'You already joined this event');
    }
    const first = db.prepare('SELECT COUNT(*) c FROM volunteers WHERE issue_id=?').get(id).c === 0;
    db.prepare('INSERT INTO volunteers (issue_id,user_id,role,joined_at) VALUES (?,?,?,?)')
      .run(id, user.id, first ? 'organiser' : 'volunteer', now());
    if (first) {
      db.prepare("UPDATE issues SET status='in_progress' WHERE id=?").run(id);
      addHistory(id, 'in_progress', `${user.name} became the organiser`, user.id);
    } else {
      addHistory(id, 'in_progress', `${user.name} joined as a volunteer`, user.id);
    }
    const rewards = award(user.id, POINTS.join, ['Joined an event']);
    return { issue: issueView(issueRow(id), user, me), rewards };
  });
}

export function leaveEvent(user, id) {
  return tx(() => {
    const issue = eventOrThrow(id, ['event', 'in_progress']);
    const v = db.prepare('SELECT * FROM volunteers WHERE issue_id=? AND user_id=?').get(id, user.id);
    if (!v) throw new ApiError(409, 'NOT_JOINED', 'You have not joined this event');
    db.prepare('DELETE FROM volunteers WHERE issue_id=? AND user_id=?').run(id, user.id);
    const rest = db.prepare('SELECT user_id FROM volunteers WHERE issue_id=? ORDER BY joined_at').all(id);
    if (!rest.length) {
      db.prepare("UPDATE issues SET status='event' WHERE id=?").run(id);
      addHistory(id, 'event', 'All volunteers left. Looking for volunteers again', user.id);
    } else if (v.role === 'organiser') {
      db.prepare("UPDATE volunteers SET role='organiser' WHERE issue_id=? AND user_id=?").run(id, rest[0].user_id);
    }
    return { issue: issueView(issueRow(id), user) };
  });
}

export function scheduleEvent(user, id, body) {
  const issue = eventOrThrow(id, ['event', 'in_progress']);
  const org = db.prepare("SELECT 1 x FROM volunteers WHERE issue_id=? AND user_id=? AND role='organiser'").get(id, user.id);
  if (!org) throw new ApiError(403, 'NOT_ORGANISER', 'Only the organiser can reschedule');
  const at = Number(body.scheduledAt);
  if (!Number.isFinite(at) || at < now() - DAY) throw new ApiError(400, 'BAD_DATE', 'Pick a valid future date');
  db.prepare('UPDATE issues SET scheduled_at=? WHERE id=?').run(at, id);
  addHistory(id, issue.status, `Scheduled for ${new Date(at).toDateString()}`, user.id);
  const vols = db.prepare('SELECT user_id FROM volunteers WHERE issue_id=? AND user_id!=?').all(id, user.id);
  for (const v of vols) notify(v.user_id, 'event_scheduled', 'Event rescheduled', `"${issue.title}" is now on ${new Date(at).toDateString()}`, id);
  return { issue: issueView(issueRow(id), user) };
}

export function resolveEvent(user, id, body) {
  const me = parseLoc(body.lat, body.lng, 'current location');
  touchLocation(user, me.lat, me.lng);
  return tx(() => {
    const issue = eventOrThrow(id, ['in_progress']);
    const vol = db.prepare('SELECT 1 x FROM volunteers WHERE issue_id=? AND user_id=?').get(id, user.id);
    if (!vol) throw new ApiError(403, 'NOT_VOLUNTEER', 'Only volunteers of this event can mark it resolved');
    const note = String(body.note || '').trim() || 'Work completed';
    db.prepare("UPDATE issues SET status='pending_verification', resolved_at=?, resolution_note=? WHERE id=?").run(now(), note, id);
    addHistory(id, 'pending_verification', `Marked resolved: ${note}`, user.id);
    const sups = db.prepare('SELECT user_id FROM supports WHERE issue_id=?').all(id);
    const vols = new Set(db.prepare('SELECT user_id FROM volunteers WHERE issue_id=?').all(id).map((v) => v.user_id));
    for (const s of sups) {
      if (!vols.has(s.user_id)) notify(s.user_id, 'verify_request', 'Is it really fixed?', `Please verify "${issue.title}" if you are nearby`, id);
    }
    return { issue: issueView(issueRow(id), user, me, true) };
  });
}

export function verifyEvent(user, id, body) {
  const me = parseLoc(body.lat, body.lng, 'current location');
  touchLocation(user, me.lat, me.lng);
  return tx(() => {
    const issue = eventOrThrow(id, ['pending_verification']);
    const sup = db.prepare('SELECT 1 x FROM supports WHERE issue_id=? AND user_id=?').get(id, user.id);
    if (!sup) throw new ApiError(403, 'NOT_SUPPORTER', 'Only supporters of the original issue can verify');
    const vol = db.prepare('SELECT 1 x FROM volunteers WHERE issue_id=? AND user_id=?').get(id, user.id);
    if (vol) throw new ApiError(403, 'IS_VOLUNTEER', 'Volunteers cannot verify their own work');
    requireWithin(user, me.lat, me.lng, issue, radiusFor(issue.category));
    if (db.prepare('SELECT 1 x FROM verifications WHERE issue_id=? AND user_id=? AND round=?').get(id, user.id, issue.round)) {
      throw new ApiError(409, 'ALREADY', 'You already voted');
    }
    const approve = body.approve ? 1 : 0;
    db.prepare('INSERT INTO verifications (issue_id,user_id,round,approve,created_at) VALUES (?,?,?,?,?)')
      .run(id, user.id, issue.round, approve, now());
    let rewards = award(user.id, POINTS.verify, [approve ? 'Verified a fix' : 'Reported an incomplete fix']);
    const tally = db.prepare('SELECT approve, COUNT(*) c FROM verifications WHERE issue_id=? AND round=? GROUP BY approve').all(id, issue.round);
    const yes = tally.find((t) => t.approve === 1)?.c || 0;
    const no = tally.find((t) => t.approve === 0)?.c || 0;
    let outcome = 'pending';
    if (yes >= CONFIG.verifyNeeded) {
      outcome = 'closed';
      db.prepare("UPDATE issues SET status='closed', closed_at=?, authority_status='resolved' WHERE id=?").run(now(), id);
      addHistory(id, 'closed', 'Resolution verified by neighbours');
      const vols = db.prepare('SELECT user_id FROM volunteers WHERE issue_id=?').all(id);
      for (const v of vols) {
        const r = award(v.user_id, POINTS.closedVolunteer, ['Event closed. Great work!']);
        notify(v.user_id, 'event_closed', 'Event closed', `"${issue.title}" was verified as resolved`, id);
        if (v.user_id === user.id) rewards = mergeRewards(rewards, r);
      }
      award(issue.reporter_id, POINTS.closedReporter, ['Your reported issue was resolved']);
      notify(issue.reporter_id, 'event_closed', 'Your issue is resolved', `"${issue.title}" was verified as fixed`, id);
    } else if (no >= CONFIG.verifyNeeded) {
      outcome = 'reopened';
      db.prepare("UPDATE issues SET status='in_progress', round=round+1, resolved_at=NULL, authority_status='in_progress' WHERE id=?").run(id);
      addHistory(id, 'in_progress', 'Neighbours say the work is not finished. Back in progress');
      const vols = db.prepare('SELECT user_id FROM volunteers WHERE issue_id=?').all(id);
      for (const v of vols) notify(v.user_id, 'event_reopened', 'Resolution rejected', `Neighbours say "${issue.title}" still needs work`, id);
    }
    return { issue: issueView(issueRow(id), user, me, true), outcome, rewards };
  });
}

// ---------- Neta stats ----------
export function descendantIds(id) {
  const all = db.prepare('SELECT id, parent_id FROM politicians').all();
  const out = [id];
  let frontier = [id];
  while (frontier.length) {
    const next = all.filter((p) => frontier.includes(p.parent_id)).map((p) => p.id);
    out.push(...next);
    frontier = next;
  }
  return out;
}

export function rarityFor(rate, closed, sampleOk) {
  if (!sampleOk) return 'unrated';
  if (rate >= 0.85 && closed >= 10) return 'legendary';
  if (rate >= 0.65) return 'epic';
  if (rate >= 0.4) return 'rare';
  return 'common';
}

export function netaStats(id) {
  const ids = descendantIds(id);
  const rows = db.prepare(`
    SELECT i.id, i.status, i.category, i.created_at, i.closed_at,
      (SELECT COUNT(*) FROM supports s WHERE s.issue_id=i.id) sc,
      (SELECT COUNT(*) FROM linked_reports l WHERE l.issue_id=i.id) lc
    FROM issues i WHERE i.politician_id IN (${ids.map(() => '?').join(',')})`).all(...ids);
  let reported = rows.length;
  let resolved = 0, open = 0, critOpen = 0, wAll = 0, wDone = 0, days = 0;
  for (const r of rows) {
    const sev = severityOf(r.sc, r.lc, r.created_at, r.category).level;
    const w = SEVERITY_WEIGHT[sev];
    wAll += w;
    if (r.status === 'closed') {
      resolved++; wDone += w;
      days += (r.closed_at - r.created_at) / DAY;
    } else {
      open++;
      if (sev === 'critical') critOpen++;
    }
  }
  const sampleOk = reported >= CONFIG.minNetaSample;
  const simpleRate = reported ? resolved / reported : 0;
  const rate = wAll ? wDone / wAll : 0;
  return {
    reported, resolved, open,
    criticalOpen: critOpen,
    rate: sampleOk ? Math.round(rate * 1000) / 1000 : null,
    simpleRate: Math.round(simpleRate * 1000) / 1000,
    avgDaysToResolve: resolved ? Math.round((days / resolved) * 10) / 10 : null,
    sampleOk,
    minSample: CONFIG.minNetaSample,
    rarity: rarityFor(rate, resolved, sampleOk),
  };
}

export function netaView(p, withStats = true) {
  const parent = p.parent_id ? db.prepare('SELECT id,name,level,party FROM politicians WHERE id=?').get(p.parent_id) : null;
  const nm = (id) => (id ? areaById(id)?.name ?? null : null);
  return {
    id: p.id, name: p.name, party: p.party, constituency: p.constituency,
    level: p.level, hue: p.hue, tagline: p.tagline,
    city: nm(p.city_id), state: nm(p.state_id), region: nm(p.region_id),
    cityId: p.city_id, stateId: p.state_id, regionId: p.region_id,
    parent: parent ? { id: parent.id, name: parent.name, level: parent.level, party: parent.party } : null,
    ...(withStats ? { stats: netaStats(p.id) } : {}),
  };
}

export function netaTree(sc = { scope: 'all', area: null }) {
  const all = db.prepare('SELECT * FROM politicians').all();
  const build = (p) => ({
    ...netaView(p),
    children: all.filter((c) => c.parent_id === p.id && leaderInScope(c, sc)).map(build),
  });
  return all.filter((p) => !p.parent_id && leaderInScope(p, sc)).map(build);
}

export function userProfile(user) {
  const rank = rankFor(user.points);
  const earned = db.prepare('SELECT badge_key, earned_at FROM user_badges WHERE user_id=?').all(user.id);
  const earnedMap = new Map(earned.map((e) => [e.badge_key, e.earned_at]));
  const s = badgeStats(user.id);
  return {
    id: user.id, name: user.name, email: user.email, hue: user.hue,
    role: user.role || 'citizen', orgName: user.org_name || null, regNo: user.reg_no || null,
    verified: !!user.verified, verificationStatus: user.verify_status || 'verified',
    about: user.about || '', needs: parseJson(user.needs, []), address: user.address || '',
    departmentName: user.department_name || null, politicianId: user.politician_id || null,
    designation: user.designation || null, cityId: user.city_id || null,
    avatarUrl: user.avatar_url || null, coverUrl: user.cover_url || null,
    points: user.points, rank,
    volunteer: !!user.volunteer, alertRadiusKm: user.alert_radius_km,
    home: user.home_lat != null ? { lat: user.home_lat, lng: user.home_lng } : null,
    createdAt: user.created_at,
    stats: { reports: s.reports, supports: s.supports, joins: s.joins, verifies: s.verifies, closedHelped: s.closedHelped, meals: s.meals },
    badges: BADGES.map((b) => ({ ...b, earned: earnedMap.has(b.key), earnedAt: earnedMap.get(b.key) || null })),
  };
}
