// Read-only analytics for the Insights screen and the impact counter.
// Everything is derived from donations, donation_history, gatherings and gathering_rsvps.
// Scope follows the signed-in user:
//   citizen    -> what they donated and the gatherings they joined
//   foundation -> what they claimed and the gatherings they hosted
//   admin/neta -> city-wide numbers
import { db } from './db.js';
import { DONATION_KINDS, GATHERING_TYPES } from './config.js';
import { DAY } from './util.js';
import { authUser } from './auth.js';
import { donationRows } from './donations.js';
import { gatheringRows } from './gatherings.js';

const WEEK = 7 * DAY;
const ALL_TIME = Number.MAX_SAFE_INTEGER;

const count = (sql, ...p) => db.prepare(sql).get(...p).c;
const round3 = (n) => Math.round(n * 1000) / 1000;

/** Donations visible to this user (SQL fragment against alias `d`). */
function donationScope(user) {
  if (user.role === 'citizen') return { sql: 'd.donor_id=?', p: [user.id] };
  if (user.role === 'foundation') return { sql: 'd.claimed_by=?', p: [user.id] };
  return { sql: '1=1', p: [] };
}

/** Gatherings visible to this user (SQL fragment against alias `g`). */
function gatheringScope(user) {
  if (user.role === 'citizen') return { sql: 'g.id IN (SELECT gathering_id FROM gathering_rsvps WHERE user_id=?)', p: [user.id] };
  if (user.role === 'foundation') return { sql: 'g.organizer_id=?', p: [user.id] };
  return { sql: '1=1', p: [] };
}

/**
 * Events joined: citizens count their own RSVPs, foundations count the gatherings they hosted,
 * admin/neta count every RSVP in the city.
 */
function eventCount(user, from, to) {
  if (user.role === 'citizen') {
    return count('SELECT COUNT(*) c FROM gathering_rsvps r WHERE r.user_id=? AND r.created_at>=? AND r.created_at<=?', user.id, from, to);
  }
  if (user.role === 'foundation') {
    return count('SELECT COUNT(*) c FROM gatherings g WHERE g.organizer_id=? AND g.created_at>=? AND g.created_at<=?', user.id, from, to);
  }
  return count('SELECT COUNT(*) c FROM gathering_rsvps r WHERE r.created_at>=? AND r.created_at<=?', from, to);
}

/**
 * Claim rate = share of donations created in the window that were claimed (have a 'claimed' history row).
 * Citizens: of their own donations. Foundations: of all donations in the city, the share they claimed.
 * Admin/neta: of all donations in the city.
 */
function claimRate(user, from, to) {
  const claimedOnly = donationScope(user);
  const denomScope = user.role === 'foundation' ? { sql: '1=1', p: [] } : claimedOnly;
  const total = count(
    `SELECT COUNT(*) c FROM donations d WHERE ${denomScope.sql} AND d.created_at>=? AND d.created_at<=?`,
    ...denomScope.p, from, to,
  );
  if (!total) return 0;
  const claimed = count(
    `SELECT COUNT(*) c FROM donations d WHERE ${claimedOnly.sql} AND d.created_at>=? AND d.created_at<=?
       AND EXISTS (SELECT 1 FROM donation_history h WHERE h.donation_id=d.id AND h.status='claimed')`,
    ...claimedOnly.p, from, to,
  );
  return round3(claimed / total);
}

/** The raw numbers for one time window. */
function windowStats(user, from, to) {
  const ds = donationScope(user);
  return {
    // people reached = beneficiaries recorded when a donation was distributed in the window
    people: count(
      `SELECT COALESCE(SUM(COALESCE(d.dist_beneficiaries,0)),0) c FROM donations d
         WHERE ${ds.sql} AND d.status='distributed' AND d.distributed_at>=? AND d.distributed_at<=?`,
      ...ds.p, from, to,
    ),
    items: count(`SELECT COUNT(*) c FROM donations d WHERE ${ds.sql} AND d.created_at>=? AND d.created_at<=?`, ...ds.p, from, to),
    events: eventCount(user, from, to),
    claimRate: claimRate(user, from, to),
  };
}

/** Activity per local calendar day, oldest first, ending today. */
function weekly(user, now) {
  const out = [];
  const midnight = (offset) => {
    const d = new Date(now);
    d.setHours(0, 0, 0, 0);
    d.setDate(d.getDate() + offset);
    return d;
  };
  for (let i = -6; i <= 0; i += 1) {
    const start = midnight(i);
    const end = midnight(i + 1).getTime() - 1;
    const s = windowStats(user, start.getTime(), end);
    out.push({ day: start.toLocaleDateString('en-US', { weekday: 'short' }), value: s.items + s.events });
  }
  return out;
}

/** Up to five most recent donations and gatherings in scope. */
function topItems(user, limit = 5) {
  const ds = donationScope(user);
  const donations = donationRows(`WHERE ${ds.sql} ORDER BY d.created_at DESC LIMIT ?`, ...ds.p, limit)
    .map((d) => ({
      id: d.id,
      kind: 'donation',
      title: d.title,
      subtitle: `${DONATION_KINDS[d.kind] || 'Other'} · ${d.quantity}`,
      rate: db.prepare("SELECT 1 x FROM donation_history WHERE donation_id=? AND status='claimed'").get(d.id) ? 1 : 0,
      when: d.created_at,
    }));
  const gs = gatheringScope(user);
  const gatherings = gatheringRows(`WHERE ${gs.sql} ORDER BY g.start_at DESC LIMIT ?`, ...gs.p, limit)
    .map((g) => ({
      id: g.id,
      kind: 'gathering',
      title: g.title,
      subtitle: `${GATHERING_TYPES[g.type] || g.type}${g.address ? ` · ${g.address}` : ''}`,
      rate: g.going_count ? round3(g.checked_in_count / g.going_count) : 0,
      when: g.start_at,
    }));
  return [...donations, ...gatherings].sort((a, b) => b.when - a.when).slice(0, limit);
}

export function insightsFor(user, now = Date.now()) {
  const from = now - WEEK;
  const prevFrom = now - 2 * WEEK;
  const prevTo = from - 1;
  const cur = windowStats(user, from, now);
  const prev = windowStats(user, prevFrom, prevTo);
  const metric = (key, label, value, delta) => ({
    key, label, value, delta, deltaLabel: 'vs last 7 days', positive: delta >= 0,
  });
  return {
    period: { from, to: now },
    metrics: [
      metric('people_reached', 'People reached', cur.people, cur.people - prev.people),
      metric('items_donated', 'Items donated', cur.items, cur.items - prev.items),
      metric('events_joined', 'Events joined', cur.events, cur.events - prev.events),
      metric('claim_rate', 'Claim rate', cur.claimRate, round3(cur.claimRate - prev.claimRate)),
    ],
    weekly: weekly(user, now),
    top: topItems(user),
  };
}

export function impactFor(user) {
  const ds = donationScope(user);
  // Volunteer hours are an estimate: every event joined counts as 3 hours of volunteering.
  const events = eventCount(user, 0, ALL_TIME);
  return {
    meals: count(
      `SELECT COALESCE(SUM(COALESCE(d.dist_beneficiaries,0)),0) c FROM donations d
         WHERE ${ds.sql} AND d.kind='food' AND d.status='distributed'`,
      ...ds.p,
    ),
    items: count(`SELECT COUNT(*) c FROM donations d WHERE ${ds.sql} AND d.status='distributed'`, ...ds.p),
    events,
    volunteerHours: events * 3,
  };
}

export function registerInsightRoutes(app) {
  app.get('/insights', async (req) => insightsFor(authUser(req)));
  app.get('/impact', async (req) => impactFor(authUser(req)));
}
