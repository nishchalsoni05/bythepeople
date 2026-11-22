// Feed 2: social-good gatherings (drives, runs, camps), proposals/campaigns, clubs and the calendar.
import { db, tx } from './db.js';
import { CONFIG, POINTS, GATHERING_TYPES } from './config.js';
import { now, haversineKm, ApiError, num } from './util.js';
import { authUser } from './auth.js';
import {
  parseJson, cleanMedia, publicUrl, userRef, userRefFromRow, likeCount, commentCount, likedBy, getLoc, IST_OFFSET_MS,
} from './common.js';
import { award, notify, parseLoc, touchLocation, round1 } from './logic.js';

const HOUR = 3600000;
const MIN = 60000;

const GATHERING_SQL = `
SELECT g.*,
  (SELECT COUNT(*) FROM gathering_rsvps r WHERE r.gathering_id=g.id) AS going_count,
  (SELECT COUNT(*) FROM gathering_rsvps r WHERE r.gathering_id=g.id AND r.checked_in_at IS NOT NULL) AS checked_in_count,
  (SELECT COUNT(*) FROM gathering_votes v WHERE v.gathering_id=g.id) AS vote_count,
  c.name AS club_name
FROM gatherings g LEFT JOIN clubs c ON c.id=g.club_id`;

export const gatheringRows = (where = '', ...p) => db.prepare(`${GATHERING_SQL} ${where}`).all(...p);
export const gatheringRow = (id) => db.prepare(`${GATHERING_SQL} WHERE g.id=?`).get(id);

export const endOf = (g) => g.end_at ?? g.start_at + CONFIG.checkinDefaultHours * HOUR;

/** Stored status + time => proposed|upcoming|ongoing|completed|cancelled. */
export function statusOf(g, t = now()) {
  if (g.status === 'cancelled' || g.status === 'completed') return g.status;
  if (g.status === 'proposed') return endOf(g) < t ? 'cancelled' : 'proposed';
  if (t >= endOf(g)) return 'completed';
  if (t >= g.start_at) return 'ongoing';
  return 'upcoming';
}

const fmtWhen = (ms) => new Date(ms).toLocaleString('en-IN', {
  timeZone: 'Asia/Kolkata', weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit',
});

export function gatheringView(g, user, loc = null, detail = false) {
  const status = statusOf(g);
  const going = g.going_count;
  const likes = likeCount('gathering', g.id);
  const comments = commentCount('gathering', g.id);
  const url = publicUrl('gathering', g.id);
  const view = {
    id: g.id, title: g.title, description: g.description, type: g.type,
    typeLabel: GATHERING_TYPES[g.type] || 'Other',
    lat: g.lat, lng: g.lng, address: g.address, startAt: g.start_at, endAt: g.end_at,
    status,
    organizer: userRef(g.organizer_id),
    club: g.club_id ? { id: g.club_id, name: g.club_name } : null,
    capacity: g.capacity, media: parseJson(g.media, []),
    goingCount: going,
    spotsLeft: g.capacity == null ? null : Math.max(0, g.capacity - going),
    goingByMe: false, checkedInByMe: false,
    voteCount: g.vote_count, votesNeeded: CONFIG.campaignVotes, votedByMe: false,
    likeCount: likes, likedByMe: likedBy('gathering', g.id, user),
    commentCount: comments, shareCount: g.share_count,
    shareText: status === 'proposed'
      ? `Campaign proposal: "${g.title}". ${g.vote_count} of ${CONFIG.campaignVotes} votes so far. Back it here: ${url}`
      : `Join "${g.title}" on ${fmtWhen(g.start_at)}${g.address ? ` at ${g.address}` : ''}. ${going} people are going. ${url}`,
    publicUrl: url,
    attendees: db.prepare(`SELECT u.id,u.name,u.hue FROM gathering_rsvps r JOIN users u ON u.id=r.user_id
      WHERE r.gathering_id=? ORDER BY r.created_at LIMIT ?`).all(g.id, detail ? 50 : 6),
    isOrganiser: !!user && g.organizer_id === user.id,
  };
  if (status === 'completed') view.impact = { checkedIn: g.checked_in_count, note: g.impact_note || '' };
  if (loc) view.distanceKm = round1(haversineKm(loc.lat, loc.lng, g.lat, g.lng));
  if (user) {
    const r = db.prepare('SELECT checked_in_at FROM gathering_rsvps WHERE gathering_id=? AND user_id=?').get(g.id, user.id);
    view.goingByMe = !!r;
    view.checkedInByMe = !!r?.checked_in_at;
    view.votedByMe = !!db.prepare('SELECT 1 x FROM gathering_votes WHERE gathering_id=? AND user_id=?').get(g.id, user.id);
  }
  return view;
}

const viewById = (id, user, loc, detail = false) => gatheringView(gatheringRow(id), user, loc, detail);

function mustGet(id) {
  const g = gatheringRow(id);
  if (!g) throw new ApiError(404, 'NOT_FOUND', 'Gathering not found');
  return g;
}

export function gatheringViewById(id, user, loc = null) {
  const g = gatheringRow(id);
  return g ? gatheringView(g, user, loc) : null;
}

/** Gatherings a user RSVP'd to. */
export function gatheringsForUser(user, loc) {
  return gatheringRows('WHERE g.id IN (SELECT gathering_id FROM gathering_rsvps WHERE user_id=?) ORDER BY g.start_at DESC', user.id)
    .map((g) => gatheringView(g, user, loc));
}

export function nextGatherings(user, loc, limit) {
  return gatheringRows('ORDER BY g.start_at').filter((g) => ['upcoming', 'ongoing'].includes(statusOf(g)))
    .slice(0, limit).map((g) => gatheringView(g, user, loc));
}

/** Called by the 30s interval: reminders for gatherings starting within the hour. */
export function sendGatheringReminders() {
  const t = now();
  for (const g of gatheringRows("WHERE g.status='upcoming' AND g.reminded=0 AND g.start_at>? AND g.start_at<=?", t, t + CONFIG.reminderMinutes * MIN)) {
    db.prepare('UPDATE gatherings SET reminded=1 WHERE id=?').run(g.id);
    for (const r of db.prepare('SELECT user_id FROM gathering_rsvps WHERE gathering_id=?').all(g.id)) {
      notify(r.user_id, 'gathering_reminder', 'Starting soon', `"${g.title}" starts at ${fmtWhen(g.start_at)}`, null, 'gathering', g.id);
    }
  }
}

function parseCreate(user, b) {
  const title = String(b.title || '').trim();
  if (title.length < 4) throw new ApiError(400, 'BAD_TITLE', 'Give your gathering a title (4+ characters)');
  if (!GATHERING_TYPES[b.type]) throw new ApiError(400, 'BAD_TYPE', `Pick a type: ${Object.keys(GATHERING_TYPES).join(', ')}`);
  const loc = parseLoc(b.lat, b.lng, 'venue location');
  const startAt = Number(b.startAt);
  if (!Number.isFinite(startAt) || startAt <= now()) throw new ApiError(400, 'BAD_DATE', 'The start time must be in the future');
  let endAt = null;
  if (b.endAt !== undefined && b.endAt !== null && b.endAt !== '') {
    endAt = Number(b.endAt);
    if (!Number.isFinite(endAt) || endAt <= startAt) throw new ApiError(400, 'BAD_DATE', 'The end time must be after the start time');
  }
  let capacity = null;
  if (b.capacity !== undefined && b.capacity !== null && b.capacity !== '') {
    capacity = Number(b.capacity);
    if (!Number.isInteger(capacity) || capacity < 1) throw new ApiError(400, 'BAD_CAPACITY', 'Capacity must be a whole number of 1 or more');
  }
  let clubId = null;
  if (b.clubId !== undefined && b.clubId !== null && b.clubId !== '') {
    clubId = Number(b.clubId);
    if (!db.prepare('SELECT 1 x FROM clubs WHERE id=?').get(clubId)) throw new ApiError(404, 'NOT_FOUND', 'Club not found');
  }
  return {
    title, description: String(b.description || '').trim(), type: b.type, ...loc,
    address: b.address ? String(b.address) : null, startAt, endAt, capacity, clubId,
    media: cleanMedia(b.media), proposed: !!b.proposed,
  };
}

// ---------- clubs ----------
function clubView(c, user) {
  const members = db.prepare('SELECT COUNT(*) c FROM club_members WHERE club_id=?').get(c.id).c;
  const upcoming = gatheringRows('WHERE g.club_id=?', c.id).filter((g) => ['upcoming', 'ongoing'].includes(statusOf(g))).length;
  return {
    id: c.id, name: c.name, description: c.description, category: c.category, hue: c.hue,
    avatarUrl: c.avatar_url || null, coverUrl: c.cover_url || null,
    memberCount: members,
    joinedByMe: !!user && !!db.prepare('SELECT 1 x FROM club_members WHERE club_id=? AND user_id=?').get(c.id, user.id),
    owner: userRef(c.owner_id), upcomingCount: upcoming,
  };
}

export function registerGatheringRoutes(app) {
  // ---------- calendar (before /:id) ----------
  app.get('/gatherings/calendar', async (req) => {
    authUser(req);
    let month = String(req.query.month || '');
    if (!month) month = new Date(now() + IST_OFFSET_MS).toISOString().slice(0, 7);
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) throw new ApiError(400, 'BAD_MONTH', 'month must look like 2026-11');
    const days = {};
    for (const g of gatheringRows('ORDER BY g.start_at')) {
      const st = statusOf(g);
      if (st === 'cancelled') continue;
      const key = new Date(g.start_at + IST_OFFSET_MS).toISOString().slice(0, 10);
      if (!key.startsWith(month)) continue;
      (days[key] ||= []).push({ id: g.id, title: g.title, type: g.type, startAt: g.start_at, status: st });
    }
    return { days };
  });

  app.get('/gatherings', async (req) => {
    const user = authUser(req);
    const q = req.query;
    const loc = getLoc(q);
    const when = q.when || 'upcoming';
    if (!['upcoming', 'past', 'mine', 'proposed'].includes(when)) throw new ApiError(400, 'BAD_FILTER', 'when must be upcoming, past, mine or proposed');
    let rows = gatheringRows();
    rows = rows.filter((g) => {
      const st = statusOf(g);
      if (when === 'upcoming') return st === 'upcoming' || st === 'ongoing';
      if (when === 'past') return st === 'completed';
      if (when === 'proposed') return st === 'proposed';
      return g.organizer_id === user.id
        || !!db.prepare('SELECT 1 x FROM gathering_rsvps WHERE gathering_id=? AND user_id=?').get(g.id, user.id);
    });
    if (q.type) rows = rows.filter((g) => g.type === q.type);
    if (q.club) rows = rows.filter((g) => String(g.club_id) === String(q.club));
    if (q.q) {
      const n = String(q.q).toLowerCase();
      rows = rows.filter((g) => g.title.toLowerCase().includes(n) || g.description.toLowerCase().includes(n) || (g.address || '').toLowerCase().includes(n));
    }
    let items = rows.map((g) => gatheringView(g, user, loc));
    const sort = q.sort || (when === 'past' ? 'recent' : when === 'proposed' ? 'popular' : 'soon');
    if (sort === 'near' && loc) items.sort((a, b) => a.distanceKm - b.distanceKm);
    else if (sort === 'popular') items.sort((a, b) => (b.goingCount + b.voteCount) - (a.goingCount + a.voteCount) || a.startAt - b.startAt);
    else if (sort === 'recent') items.sort((a, b) => b.startAt - a.startAt);
    else items.sort((a, b) => a.startAt - b.startAt);
    return { items };
  });

  app.get('/gatherings/:id', async (req) => {
    const user = authUser(req);
    return { gathering: gatheringView(mustGet(Number(req.params.id) || 0), user, getLoc(req.query), true) };
  });

  app.post('/gatherings', async (req, reply) => {
    const user = authUser(req);
    const d = parseCreate(user, req.body || {});
    const info = db.prepare(`INSERT INTO gatherings (title,description,type,lat,lng,address,start_at,end_at,status,organizer_id,club_id,capacity,media,created_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
      .run(d.title, d.description, d.type, d.lat, d.lng, d.address, d.startAt, d.endAt, d.proposed ? 'proposed' : 'upcoming',
        user.id, d.clubId, d.capacity, JSON.stringify(d.media), now());
    reply.status(201);
    return { gathering: viewById(Number(info.lastInsertRowid), user, null, true) };
  });

  // ---------- RSVP ----------
  app.post('/gatherings/:id/rsvp', async (req) => {
    const user = authUser(req);
    const id = Number(req.params.id) || 0;
    return tx(() => {
      const g = mustGet(id);
      const st = statusOf(g);
      if (st === 'proposed') throw new ApiError(409, 'NOT_OPEN', 'This is still a proposal. Vote for it to make it happen.');
      if (st === 'cancelled') throw new ApiError(409, 'CANCELLED', 'This gathering was cancelled');
      if (st === 'completed') throw new ApiError(409, 'ENDED', 'This gathering has already ended');
      if (db.prepare('SELECT 1 x FROM gathering_rsvps WHERE gathering_id=? AND user_id=?').get(id, user.id)) {
        throw new ApiError(409, 'ALREADY', 'You are already going');
      }
      if (g.capacity != null && g.going_count >= g.capacity) throw new ApiError(409, 'FULL', 'Sorry, this gathering is full');
      db.prepare('INSERT INTO gathering_rsvps (gathering_id,user_id,created_at) VALUES (?,?,?)').run(id, user.id, now());
      let rewards = null;
      const first = !db.prepare('SELECT 1 x FROM gathering_rsvp_awards WHERE gathering_id=? AND user_id=?').get(id, user.id);
      if (first) {
        db.prepare('INSERT INTO gathering_rsvp_awards (gathering_id,user_id) VALUES (?,?)').run(id, user.id);
        rewards = award(user.id, POINTS.rsvp, ['You are going to a gathering']);
      }
      if (g.organizer_id !== user.id) {
        notify(g.organizer_id, 'rsvp', 'New RSVP', `${user.name} is going to "${g.title}"`, null, 'gathering', id);
      }
      return { gathering: viewById(id, user), rewards };
    });
  });

  app.delete('/gatherings/:id/rsvp', async (req) => {
    const user = authUser(req);
    const id = Number(req.params.id) || 0;
    const g = mustGet(id);
    const r = db.prepare('SELECT * FROM gathering_rsvps WHERE gathering_id=? AND user_id=?').get(id, user.id);
    if (!r) throw new ApiError(409, 'NOT_GOING', 'You have not RSVP\'d to this gathering');
    if (r.checked_in_at) throw new ApiError(409, 'CHECKED_IN', 'You already checked in, so the RSVP cannot be withdrawn');
    if (statusOf(g) === 'completed') throw new ApiError(409, 'ENDED', 'This gathering has already ended');
    db.prepare('DELETE FROM gathering_rsvps WHERE gathering_id=? AND user_id=?').run(id, user.id);
    return { gathering: viewById(id, user) };
  });

  // ---------- campaign votes ----------
  app.post('/gatherings/:id/vote', async (req) => {
    const user = authUser(req);
    const id = Number(req.params.id) || 0;
    return tx(() => {
      const g = mustGet(id);
      if (statusOf(g) !== 'proposed') throw new ApiError(409, 'NOT_PROPOSED', 'Only campaign proposals can be voted on');
      if (db.prepare('SELECT 1 x FROM gathering_votes WHERE gathering_id=? AND user_id=?').get(id, user.id)) {
        throw new ApiError(409, 'ALREADY', 'You already voted for this proposal');
      }
      db.prepare('INSERT INTO gathering_votes (gathering_id,user_id,created_at) VALUES (?,?,?)').run(id, user.id, now());
      const votes = db.prepare('SELECT COUNT(*) c FROM gathering_votes WHERE gathering_id=?').get(id).c;
      let flipped = false;
      if (votes >= CONFIG.campaignVotes) {
        db.prepare("UPDATE gatherings SET status='upcoming' WHERE id=?").run(id);
        flipped = true;
        notify(g.organizer_id, 'event_created', 'Your campaign is a go!',
          `"${g.title}" reached ${CONFIG.campaignVotes} votes and is now an upcoming gathering`, null, 'gathering', id);
      }
      return { gathering: viewById(id, user), flipped };
    });
  });

  app.delete('/gatherings/:id/vote', async (req) => {
    const user = authUser(req);
    const id = Number(req.params.id) || 0;
    const g = mustGet(id);
    if (statusOf(g) !== 'proposed') throw new ApiError(409, 'NOT_PROPOSED', 'Votes can only be withdrawn while the proposal is open');
    const r = db.prepare('DELETE FROM gathering_votes WHERE gathering_id=? AND user_id=?').run(id, user.id);
    if (!r.changes) throw new ApiError(409, 'NOT_VOTED', 'You have not voted for this proposal');
    return { gathering: viewById(id, user) };
  });

  // ---------- check-in ----------
  app.post('/gatherings/:id/checkin', async (req) => {
    const user = authUser(req);
    const id = Number(req.params.id) || 0;
    const me = parseLoc(req.body?.lat, req.body?.lng, 'current location');
    touchLocation(user, me.lat, me.lng);
    return tx(() => {
      const g = mustGet(id);
      const st = statusOf(g);
      if (st === 'proposed') throw new ApiError(409, 'NOT_OPEN', 'This is still a proposal');
      if (st === 'cancelled') throw new ApiError(409, 'CANCELLED', 'This gathering was cancelled');
      const r = db.prepare('SELECT * FROM gathering_rsvps WHERE gathering_id=? AND user_id=?').get(id, user.id);
      if (!r) throw new ApiError(403, 'NOT_RSVPD', 'RSVP to this gathering first, then check in when you arrive');
      if (r.checked_in_at) throw new ApiError(409, 'ALREADY', 'You already checked in');
      const t = now();
      if (t < g.start_at - CONFIG.checkinEarlyMinutes * MIN) {
        throw new ApiError(409, 'TOO_EARLY', `Check-in opens ${CONFIG.checkinEarlyMinutes} minutes before the start`);
      }
      if (t > endOf(g) || st === 'completed') throw new ApiError(409, 'TOO_LATE', 'Check-in has closed for this gathering');
      const d = haversineKm(me.lat, me.lng, g.lat, g.lng);
      if (d > CONFIG.checkinRadiusKm) {
        throw new ApiError(403, 'OUT_OF_RANGE',
          `You are ${Math.round(d * 1000)} m from the venue. Get within ${Math.round(CONFIG.checkinRadiusKm * 1000)} m to check in.`,
          { distanceKm: round1(d), radiusKm: CONFIG.checkinRadiusKm });
      }
      db.prepare('UPDATE gathering_rsvps SET checked_in_at=? WHERE gathering_id=? AND user_id=?').run(t, id, user.id);
      const rewards = award(user.id, POINTS.checkin, ['Checked in at a gathering']);
      return { gathering: viewById(id, user), rewards };
    });
  });

  // ---------- organiser actions ----------
  app.post('/gatherings/:id/complete', async (req) => {
    const user = authUser(req);
    const id = Number(req.params.id) || 0;
    return tx(() => {
      const g = mustGet(id);
      if (g.organizer_id !== user.id) throw new ApiError(403, 'NOT_ORGANISER', 'Only the organiser can complete this gathering');
      if (g.status === 'cancelled' || statusOf(g) === 'cancelled') throw new ApiError(409, 'CANCELLED', 'This gathering was cancelled');
      if (g.status === 'completed') throw new ApiError(409, 'ALREADY', 'This gathering is already completed');
      if (g.status === 'proposed') throw new ApiError(409, 'NOT_OPEN', 'This is still a proposal');
      if (now() < g.start_at) throw new ApiError(409, 'NOT_STARTED', 'You can complete a gathering only after it has started');
      const note = String(req.body?.note || '').trim();
      db.prepare("UPDATE gatherings SET status='completed', completed_at=?, impact_note=? WHERE id=?").run(now(), note, id);
      for (const r of db.prepare('SELECT user_id FROM gathering_rsvps WHERE gathering_id=? AND checked_in_at IS NOT NULL').all(id)) {
        notify(r.user_id, 'event_closed', 'Thanks for showing up!', note ? `"${g.title}": ${note}` : `Thank you for being part of "${g.title}"`, null, 'gathering', id);
      }
      return { gathering: viewById(id, user, null, true) };
    });
  });

  app.post('/gatherings/:id/cancel', async (req) => {
    const user = authUser(req);
    const id = Number(req.params.id) || 0;
    return tx(() => {
      const g = mustGet(id);
      if (g.organizer_id !== user.id) throw new ApiError(403, 'NOT_ORGANISER', 'Only the organiser can cancel this gathering');
      const st = statusOf(g);
      if (st === 'cancelled') throw new ApiError(409, 'CANCELLED', 'Already cancelled');
      if (st === 'completed') throw new ApiError(409, 'ENDED', 'A completed gathering cannot be cancelled');
      db.prepare("UPDATE gatherings SET status='cancelled' WHERE id=?").run(id);
      const people = new Set([
        ...db.prepare('SELECT user_id FROM gathering_rsvps WHERE gathering_id=?').all(id).map((r) => r.user_id),
        ...db.prepare('SELECT user_id FROM gathering_votes WHERE gathering_id=?').all(id).map((r) => r.user_id),
      ]);
      people.delete(user.id);
      const why = String(req.body?.note || '').trim();
      for (const uid of people) {
        notify(uid, 'gathering_cancelled', 'Gathering cancelled', `"${g.title}" was cancelled by the organiser${why ? `: ${why}` : ''}`, null, 'gathering', id);
      }
      return { gathering: viewById(id, user, null, true) };
    });
  });

  // ---------- clubs ----------
  app.get('/clubs', async (req) => {
    const user = authUser(req);
    return { items: db.prepare('SELECT * FROM clubs ORDER BY id').all().map((c) => clubView(c, user)) };
  });

  app.post('/clubs', async (req, reply) => {
    const user = authUser(req);
    const b = req.body || {};
    const name = String(b.name || '').trim();
    if (name.length < 3) throw new ApiError(400, 'BAD_NAME', 'Give the club a name (3+ characters)');
    const category = GATHERING_TYPES[b.category] ? b.category : 'other';
    if (db.prepare('SELECT 1 x FROM clubs WHERE lower(name)=lower(?)').get(name)) throw new ApiError(409, 'NAME_TAKEN', 'A club with this name already exists');
    const hue = Math.floor(Math.random() * 360);
    const id = tx(() => {
      const info = db.prepare('INSERT INTO clubs (name,description,category,hue,owner_id,created_at) VALUES (?,?,?,?,?,?)')
        .run(name, String(b.description || '').trim(), category, hue, user.id, now());
      const cid = Number(info.lastInsertRowid);
      db.prepare('INSERT INTO club_members (club_id,user_id,joined_at) VALUES (?,?,?)').run(cid, user.id, now());
      return cid;
    });
    reply.status(201);
    return { club: clubView(db.prepare('SELECT * FROM clubs WHERE id=?').get(id), user) };
  });

  const clubOr404 = (id) => {
    const c = db.prepare('SELECT * FROM clubs WHERE id=?').get(Number(id) || 0);
    if (!c) throw new ApiError(404, 'NOT_FOUND', 'Club not found');
    return c;
  };

  app.post('/clubs/:id/join', async (req) => {
    const user = authUser(req);
    const c = clubOr404(req.params.id);
    if (db.prepare('SELECT 1 x FROM club_members WHERE club_id=? AND user_id=?').get(c.id, user.id)) {
      throw new ApiError(409, 'ALREADY', 'You are already a member');
    }
    db.prepare('INSERT INTO club_members (club_id,user_id,joined_at) VALUES (?,?,?)').run(c.id, user.id, now());
    return { club: clubView(c, user) };
  });

  app.delete('/clubs/:id/join', async (req) => {
    const user = authUser(req);
    const c = clubOr404(req.params.id);
    if (c.owner_id === user.id) throw new ApiError(409, 'OWNER', 'The club owner cannot leave their own club');
    const r = db.prepare('DELETE FROM club_members WHERE club_id=? AND user_id=?').run(c.id, user.id);
    if (!r.changes) throw new ApiError(409, 'NOT_MEMBER', 'You are not a member of this club');
    return { club: clubView(c, user) };
  });

  app.get('/clubs/:id', async (req) => {
    const user = authUser(req);
    const c = clubOr404(req.params.id);
    const loc = getLoc(req.query);
    const members = db.prepare(`SELECT u.id,u.name,u.hue,u.role FROM club_members m JOIN users u ON u.id=m.user_id
      WHERE m.club_id=? ORDER BY m.joined_at LIMIT 100`).all(c.id);
    const gatherings = gatheringRows('WHERE g.club_id=? ORDER BY g.start_at', c.id)
      .filter((g) => ['upcoming', 'ongoing', 'proposed'].includes(statusOf(g)))
      .map((g) => gatheringView(g, user, loc));
    return { club: { ...clubView(c, user), members, gatherings }, members, gatherings };
  });
}
