// Feed 3: surplus donations (food, clothes, ...) claimed only by verified foundations.
import { db, tx } from './db.js';
import { CONFIG, POINTS, DONATION_KINDS } from './config.js';
import { now, haversineKm, ApiError } from './util.js';
import { authUser, authRole } from './auth.js';
import {
  parseJson, cleanMedia, publicUrl, userRef, likeCount, commentCount, likedBy, getLoc,
} from './common.js';
import { award, notify, parseLoc, round1 } from './logic.js';

const MIN = 60000;
const HOUR = 3600000;
const DAYMS = 86400000;

const DONATION_SQL = `SELECT d.*, f.name AS claimer_name, f.org_name AS claimer_org, f.hue AS claimer_hue
  FROM donations d LEFT JOIN users f ON f.id=d.claimed_by`;
export const donationRows = (where = '', ...p) => db.prepare(`${DONATION_SQL} ${where}`).all(...p);
export const donationRow = (id) => db.prepare(`${DONATION_SQL} WHERE d.id=?`).get(id);

function dh(id, status, note, userId = null) {
  db.prepare('INSERT INTO donation_history (donation_id,status,note,user_id,created_at) VALUES (?,?,?,?,?)').run(id, status, note, userId, now());
}

// ---------- foundations ----------
export const foundationLoc = (u) => {
  const la = u.home_lat ?? u.last_lat; const ln = u.home_lng ?? u.last_lng;
  return la == null ? null : { lat: la, lng: ln };
};

export function foundationStats(id) {
  const one = (sql) => db.prepare(sql).get(id);
  return {
    claimed: one("SELECT COUNT(*) c FROM donations WHERE claimed_by=? AND status IN ('claimed','picked_up','distributed')").c,
    distributed: one("SELECT COUNT(*) c FROM donations WHERE claimed_by=? AND status='distributed'").c,
    beneficiaries: one("SELECT COALESCE(SUM(dist_beneficiaries),0) c FROM donations WHERE claimed_by=? AND status='distributed'").c,
    meals: one("SELECT COALESCE(SUM(servings),0) c FROM donations WHERE kind='food' AND claimed_by=? AND status IN ('claimed','picked_up','distributed')").c,
  };
}

export function foundationView(u) {
  return {
    id: u.id, name: u.org_name || u.name, about: u.about || '', needs: parseJson(u.needs, []),
    address: u.address || '', verified: !!u.verified, regNo: u.reg_no || '', hue: u.hue,
    stats: foundationStats(u.id),
    activeClaims: db.prepare("SELECT COUNT(*) c FROM donations WHERE claimed_by=? AND status IN ('claimed','picked_up')").get(u.id).c,
    verificationStatus: u.verify_status, verificationNote: u.verify_note || null,
    contactName: u.name, avatarUrl: u.avatar_url || null, coverUrl: u.cover_url || null,
  };
}

// ---------- views ----------
function freshness(d, t) {
  const left = d.expires_at - t;
  if (d.status === 'expired' || left <= 0) return 'expired';
  if (d.kind === 'food') return left < 60 * MIN ? 'critical' : left < 120 * MIN ? 'soon' : 'fresh';
  return left < DAYMS ? 'soon' : 'fresh';
}

export function donationView(d, user, loc = null, detail = false) {
  const t = now();
  const likes = likeCount('donation', d.id);
  const url = publicUrl('donation', d.id);
  const left = Math.max(0, Math.round((d.expires_at - t) / MIN));
  const view = {
    id: d.id, kind: d.kind, kindLabel: DONATION_KINDS[d.kind] || 'Other',
    title: d.title, description: d.description, quantity: d.quantity, servings: d.servings, veg: d.veg,
    preparedAt: d.prepared_at, expiresAt: d.expires_at, expiresInMinutes: left, freshness: freshness(d, t),
    lat: d.lat, lng: d.lng, address: d.address, pickupNote: d.pickup_note || '',
    media: parseJson(d.media, []), hygieneAck: !!d.hygiene_ack,
    donor: userRef(d.donor_id), donorKind: d.donor_kind || 'donor', status: d.status,
    claimedBy: d.claimed_by ? { id: d.claimed_by, name: d.claimer_org || d.claimer_name, orgName: d.claimer_org || d.claimer_name, hue: d.claimer_hue } : null,
    claimedAt: d.claimed_at, etaAt: d.eta_at, lockExpiresAt: d.lock_expires_at,
    pickedUpAt: d.picked_up_at, distributedAt: d.distributed_at,
    distribution: d.status === 'distributed'
      ? { note: d.dist_note || '', beneficiaries: d.dist_beneficiaries || 0, media: parseJson(d.dist_media, []) } : null,
    proof: d.status === 'distributed'
      ? { media: parseJson(d.dist_media, []), note: d.dist_note || '', beneficiaries: d.dist_beneficiaries || 0, at: d.distributed_at }
      : null,
    canClaim: !!user && user.role === 'foundation' && !!user.verified && d.status === 'available' && d.expires_at > t && d.donor_id !== user.id,
    claimedByMe: !!user && d.claimed_by === user.id,
    likeCount: likes, likedByMe: likedBy('donation', d.id, user),
    commentCount: commentCount('donation', d.id), shareCount: d.share_count,
    shareText: d.kind === 'food'
      ? `Surplus food available: ${d.title} (${d.quantity}${d.servings ? `, ${d.servings} servings` : ''}) near ${d.address || 'you'}. Pick up within ${left} min. ${url}`
      : `Donation available: ${d.title} (${d.quantity}) near ${d.address || 'you'}. ${url}`,
    publicUrl: url,
  };
  if (loc) view.distanceKm = round1(haversineKm(loc.lat, loc.lng, d.lat, d.lng));
  if (detail) {
    view.timeline = db.prepare(`SELECT h.status,h.note,h.created_at,h.user_id FROM donation_history h WHERE h.donation_id=? ORDER BY h.created_at,h.id`)
      .all(d.id).map((h) => ({ status: h.status, note: h.note, createdAt: h.created_at, actor: userRef(h.user_id) }));
  }
  return view;
}

export const donationViewById = (id, user, loc = null, detail = false) => {
  const d = donationRow(id);
  return d ? donationView(d, user, loc, detail) : null;
};

function mustGet(id) {
  const d = donationRow(id);
  if (!d) throw new ApiError(404, 'NOT_FOUND', 'Donation not found');
  return d;
}

/** Notify verified foundations that are close to a (re)available donation. */
function alertFoundations(d, title = 'Donation near you') {
  for (const f of db.prepare("SELECT * FROM users WHERE role='foundation' AND verified=1").all()) {
    if (f.id === d.donor_id) continue;
    const loc = foundationLoc(f);
    if (!loc || haversineKm(loc.lat, loc.lng, d.lat, d.lng) > CONFIG.foundationAlertRadiusKm) continue;
    notify(f.id, 'donation', title, `${d.title} (${d.quantity}) is available${d.kind === 'food' ? ' and will not keep for long' : ''}`, null, 'donation', d.id);
  }
}

/** Lazy + interval maintenance: expire stale listings and release claim locks that timed out. */
export function sweepDonations() {
  const t = now();
  tx(() => {
    for (const d of donationRows("WHERE d.status IN ('available','claimed') AND d.expires_at<=?", t)) {
      db.prepare("UPDATE donations SET status='expired', lock_expires_at=NULL WHERE id=?").run(d.id);
      dh(d.id, 'expired', 'Nobody collected it in time');
      notify(d.donor_id, 'donation', 'Donation expired', `"${d.title}" was not collected in time`, null, 'donation', d.id);
      if (d.claimed_by) notify(d.claimed_by, 'donation_released', 'Claim expired', `"${d.title}" expired before pickup`, null, 'donation', d.id);
    }
    for (const d of donationRows("WHERE d.status='claimed' AND d.lock_expires_at IS NOT NULL AND d.lock_expires_at<=?", t)) {
      db.prepare("UPDATE donations SET status='available', claimed_by=NULL, claimed_at=NULL, eta_at=NULL, lock_expires_at=NULL WHERE id=?").run(d.id);
      dh(d.id, 'available', 'Claim timed out. Back on the list');
      notify(d.claimed_by, 'donation_released', 'Claim released', `"${d.title}" was not picked up in time and is available again`, null, 'donation', d.id);
      notify(d.donor_id, 'donation_released', 'Back on the list', `The claim on "${d.title}" timed out, so it is available again`, null, 'donation', d.id);
      alertFoundations(d, 'Donation available again');
    }
  });
}

export const donationsByDonor = (user, loc) =>
  donationRows('WHERE d.donor_id=? ORDER BY d.created_at DESC', user.id).map((d) => donationView(d, user, loc));

export function soonestDonations(user, loc, limit) {
  sweepDonations();
  return donationRows("WHERE d.status='available' ORDER BY d.expires_at").slice(0, limit).map((d) => donationView(d, user, loc));
}

const isTrue = (v) => v === true || v === 'true' || v === 1;

export function registerDonationRoutes(app) {
  app.get('/donations', async (req) => {
    const user = authUser(req);
    sweepDonations();
    const q = req.query;
    const loc = getLoc(q);
    const status = q.status || 'available';
    if (!['available', 'claimed', 'history', 'mine'].includes(status)) throw new ApiError(400, 'BAD_FILTER', 'status must be available, claimed, history or mine');
    let rows;
    if (status === 'available') rows = donationRows("WHERE d.status='available'");
    else if (status === 'claimed') rows = donationRows("WHERE d.status IN ('claimed','picked_up')");
    else if (status === 'history') rows = donationRows("WHERE d.status IN ('distributed','expired','cancelled')");
    else if (user.role === 'foundation') rows = donationRows('WHERE d.claimed_by=? OR d.donor_id=?', user.id, user.id);
    else rows = donationRows('WHERE d.donor_id=?', user.id);
    if (q.kind) rows = rows.filter((d) => d.kind === q.kind);
    let items = rows.map((d) => donationView(d, user, loc));
    const sort = q.sort || (status === 'available' ? 'expiring' : 'new');
    if (sort === 'near' && loc) items.sort((a, b) => a.distanceKm - b.distanceKm);
    else if (sort === 'expiring') items.sort((a, b) => a.expiresAt - b.expiresAt);
    else items.sort((a, b) => b.id - a.id);
    return { items };
  });

  app.get('/donations/:id', async (req) => {
    const user = authUser(req);
    sweepDonations();
    return { donation: donationView(mustGet(Number(req.params.id) || 0), user, getLoc(req.query), true) };
  });

  app.post('/donations', async (req, reply) => {
    const user = authUser(req);
    if (user.role === 'admin') throw new ApiError(403, 'FORBIDDEN', 'Authority accounts cannot list donations. Use a citizen or foundation account.');
    if (user.role === 'foundation' && !user.verified) throw new ApiError(403, 'NOT_VERIFIED', 'Your foundation is awaiting verification. You can share surplus once it is approved.');
    const donorKind = user.role === 'foundation' ? 'foundation' : 'donor';
    const b = req.body || {};
    const kind = b.kind;
    if (!DONATION_KINDS[kind]) throw new ApiError(400, 'BAD_KIND', `Pick what you are donating: ${Object.keys(DONATION_KINDS).join(', ')}`);
    const title = String(b.title || '').trim();
    if (title.length < 3) throw new ApiError(400, 'BAD_TITLE', 'Give the donation a short title (3+ characters)');
    const quantity = String(b.quantity || '').trim();
    if (!quantity) throw new ApiError(400, 'BAD_QUANTITY', 'Tell us the quantity, for example "20 packets" or "2 bags"');
    const loc = parseLoc(b.lat, b.lng, 'pickup location');
    const media = cleanMedia(b.media);
    const t = now();
    let servings = null; let veg = 'na'; let preparedAt = null; let expiresAt;
    if (b.servings !== undefined && b.servings !== null && b.servings !== '') {
      servings = Number(b.servings);
      if (!Number.isInteger(servings) || servings < 1) throw new ApiError(400, 'BAD_SERVINGS', 'Servings must be a whole number above zero');
    }
    if (kind === 'food') {
      preparedAt = Number(b.preparedAt);
      if (!Number.isFinite(preparedAt) || b.preparedAt === null || b.preparedAt === '') {
        throw new ApiError(400, 'BAD_PREPARED_AT', 'Tell us when the food was prepared');
      }
      if (preparedAt > t + MIN) throw new ApiError(400, 'BAD_PREPARED_AT', 'The preparation time cannot be in the future');
      if (t - preparedAt > CONFIG.foodMaxAgeHours * HOUR) {
        throw new ApiError(400, 'FOOD_TOO_OLD', `Food prepared more than ${CONFIG.foodMaxAgeHours} hours ago is not safe to share`);
      }
      if (!['veg', 'nonveg', 'mixed'].includes(b.veg)) throw new ApiError(400, 'BAD_VEG', 'Say whether the food is veg, non-veg or mixed');
      veg = b.veg;
      if (servings == null) throw new ApiError(400, 'BAD_SERVINGS', 'Tell us roughly how many people it can serve');
      if (!isTrue(b.hygieneAck)) {
        throw new ApiError(400, 'HYGIENE_REQUIRED', 'Please confirm the food was freshly prepared, stored hygienically and is safe to eat');
      }
      let shelf = Number(b.shelfHours);
      if (!Number.isFinite(shelf) || shelf <= 0) shelf = CONFIG.foodShelfHours;
      shelf = Math.min(shelf, CONFIG.foodShelfHours);
      expiresAt = preparedAt + shelf * HOUR;
      if (expiresAt <= t + 10 * MIN) throw new ApiError(400, 'FOOD_TOO_OLD', 'This food would expire before anyone could collect it');
    } else {
      expiresAt = t + CONFIG.otherShelfDays * DAYMS;
    }
    const info = db.prepare(`INSERT INTO donations (kind,title,description,quantity,servings,veg,prepared_at,expires_at,lat,lng,address,pickup_note,media,hygiene_ack,donor_id,donor_kind,status,created_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'available', ?)`)
      .run(kind, title, String(b.description || '').trim(), quantity, servings, veg, preparedAt, expiresAt, loc.lat, loc.lng,
        b.address ? String(b.address) : null, b.pickupNote ? String(b.pickupNote) : null, JSON.stringify(media), isTrue(b.hygieneAck) ? 1 : 0, user.id, donorKind, t);
    const id = Number(info.lastInsertRowid);
    dh(id, 'available', 'Listed for donation', user.id);
    alertFoundations(donationRow(id));
    reply.status(201);
    return { donation: donationView(donationRow(id), user, null, true) };
  });

  app.post('/donations/:id/claim', async (req) => {
    const user = authUser(req);
    const claimId = Number(req.params.id) || 0;
    const surplus = db.prepare('SELECT donor_kind FROM donations WHERE id=?').get(claimId)?.donor_kind === 'foundation';
    if (user.role !== 'foundation') {
      if (surplus) throw new ApiError(403, 'FORBIDDEN', 'Surplus shared by foundations can only be claimed by other verified foundations');
      throw new ApiError(403, 'FOUNDATION_ONLY', 'Only verified foundations can claim donations');
    }
    if (!user.verified) throw new ApiError(403, 'NOT_VERIFIED', 'Your foundation is awaiting verification by the authority. You can claim once it is approved.');
    sweepDonations();
    const id = Number(req.params.id) || 0;
    const eta = Number(req.body?.etaMinutes);
    if (!Number.isInteger(eta) || eta < CONFIG.claimEtaMinMinutes || eta > CONFIG.claimEtaMaxMinutes) {
      throw new ApiError(400, 'BAD_ETA', `Tell us when you can arrive: ${CONFIG.claimEtaMinMinutes} to ${CONFIG.claimEtaMaxMinutes} minutes`);
    }
    return tx(() => {
      const d = mustGet(id);
      if (d.donor_kind === 'foundation' && d.donor_id === user.id) {
        throw new ApiError(403, 'FORBIDDEN', 'Your foundation cannot claim its own surplus');
      }
      if (d.status !== 'available') {
        if (d.status === 'expired') throw new ApiError(409, 'EXPIRED', 'This donation has expired');
        if (d.status === 'cancelled') throw new ApiError(409, 'CANCELLED', 'The donor cancelled this donation');
        const who = d.claimed_by ? (d.claimer_org || d.claimer_name) : 'another foundation';
        throw new ApiError(409, 'ALREADY_CLAIMED', `Already claimed by ${who}`, {
          claimedBy: d.claimed_by ? { id: d.claimed_by, name: who, orgName: who, hue: d.claimer_hue } : null,
        });
      }
      if (d.donor_id === user.id) throw new ApiError(409, 'OWN_DONATION', 'You cannot claim your own donation');
      const t = now();
      const etaAt = t + eta * MIN;
      if (etaAt > d.expires_at) {
        throw new ApiError(400, 'ETA_TOO_LATE', `You would arrive after this expires (in ${Math.max(0, Math.round((d.expires_at - t) / MIN))} min). Pick an earlier ETA.`);
      }
      const lock = Math.max(t + CONFIG.claimLockMinutes * MIN, etaAt + 15 * MIN);
      const r = db.prepare("UPDATE donations SET status='claimed', claimed_by=?, claimed_at=?, eta_at=?, lock_expires_at=? WHERE id=? AND status='available'")
        .run(user.id, t, etaAt, lock, id);
      if (!r.changes) throw new ApiError(409, 'ALREADY_CLAIMED', 'Already claimed by another foundation');
      dh(id, 'claimed', `${user.org_name || user.name} will collect it in about ${eta} minutes`, user.id);
      notify(d.donor_id, 'donation_claimed', 'Your donation was claimed', `${user.org_name || user.name} will pick up "${d.title}" in about ${eta} min`, null, 'donation', id);
      return { donation: donationView(donationRow(id), user, null, true) };
    });
  });

  const claimerOnly = (d, user, verb) => {
    if (d.claimed_by !== user.id) throw new ApiError(403, 'NOT_CLAIMER', `Only the foundation that claimed this donation can ${verb} it`);
  };

  app.post('/donations/:id/release', async (req) => {
    const user = authUser(req);
    sweepDonations();
    const id = Number(req.params.id) || 0;
    return tx(() => {
      const d = mustGet(id);
      claimerOnly(d, user, 'release');
      if (d.status !== 'claimed') throw new ApiError(409, 'BAD_STATE', d.status === 'picked_up' ? 'You already picked this up. Distribute it instead.' : `This donation is ${d.status}`);
      db.prepare("UPDATE donations SET status='available', claimed_by=NULL, claimed_at=NULL, eta_at=NULL, lock_expires_at=NULL WHERE id=?").run(id);
      dh(id, 'available', `${user.org_name || user.name} released the claim`, user.id);
      notify(d.donor_id, 'donation_released', 'Claim released', `${user.org_name || user.name} could not collect "${d.title}". It is available again.`, null, 'donation', id);
      alertFoundations(d, 'Donation available again');
      return { donation: donationView(donationRow(id), user, null, true) };
    });
  });

  app.post('/donations/:id/pickup', async (req) => {
    const user = authUser(req);
    sweepDonations();
    const id = Number(req.params.id) || 0;
    return tx(() => {
      const d = mustGet(id);
      claimerOnly(d, user, 'mark it picked up');
      if (d.status !== 'claimed') throw new ApiError(409, 'BAD_STATE', `This donation is ${d.status.replace('_', ' ')}`);
      db.prepare("UPDATE donations SET status='picked_up', picked_up_at=?, lock_expires_at=NULL WHERE id=?").run(now(), id);
      dh(id, 'picked_up', 'Picked up', user.id);
      notify(d.donor_id, 'donation_picked_up', 'Donation picked up', `${user.org_name || user.name} collected "${d.title}"`, null, 'donation', id);
      return { donation: donationView(donationRow(id), user, null, true) };
    });
  });

  app.post('/donations/:id/distribute', async (req) => {
    const user = authUser(req);
    sweepDonations();
    const id = Number(req.params.id) || 0;
    const b = req.body || {};
    if (b.beneficiaries === undefined || b.beneficiaries === null || b.beneficiaries === '') {
      throw new ApiError(400, 'BAD_REQUEST', 'Tell us how many people benefited');
    }
    const beneficiaries = Number(b.beneficiaries);
    if (!Number.isInteger(beneficiaries) || beneficiaries < 1) throw new ApiError(400, 'BAD_BENEFICIARIES', 'Tell us how many people benefited (a whole number above zero)');
    const media = cleanMedia(b.media);
    if (!media.length) throw new ApiError(400, 'BAD_REQUEST', 'Attach at least one photo of the delivery as proof');
    return tx(() => {
      const d = mustGet(id);
      claimerOnly(d, user, 'distribute');
      if (d.status !== 'picked_up') {
        throw new ApiError(409, 'NOT_PICKED_UP', d.status === 'claimed' ? 'Mark it as picked up first' : `This donation is ${d.status}`);
      }
      const note = String(b.note || '').trim();
      db.prepare("UPDATE donations SET status='distributed', distributed_at=?, dist_note=?, dist_beneficiaries=?, dist_media=? WHERE id=?")
        .run(now(), note, beneficiaries, JSON.stringify(media), id);
      dh(id, 'distributed', `Reached ${beneficiaries} people${note ? `: ${note}` : ''}`, user.id);
      award(d.donor_id, POINTS.donationDonor, ['Your donation reached people in need']);
      notify(d.donor_id, 'donation_distributed', 'Your donation made a difference',
        `"${d.title}" reached ${beneficiaries} people via ${user.org_name || user.name}. You earned ${POINTS.donationDonor} points.`, null, 'donation', id);
      const rewards = award(user.id, POINTS.donationFoundation, ['Donation distributed']);
      return { donation: donationView(donationRow(id), user, null, true), rewards };
    });
  });

  app.post('/donations/:id/cancel', async (req) => {
    const user = authUser(req);
    sweepDonations();
    const id = Number(req.params.id) || 0;
    return tx(() => {
      const d = mustGet(id);
      if (d.donor_id !== user.id) throw new ApiError(403, 'NOT_DONOR', 'Only the donor can cancel this donation');
      if (!['available', 'claimed'].includes(d.status)) throw new ApiError(409, 'BAD_STATE', `This donation is already ${d.status.replace('_', ' ')}`);
      db.prepare("UPDATE donations SET status='cancelled', lock_expires_at=NULL WHERE id=?").run(id);
      dh(id, 'cancelled', 'Cancelled by the donor', user.id);
      if (d.claimed_by) notify(d.claimed_by, 'donation_released', 'Donation cancelled', `The donor cancelled "${d.title}"`, null, 'donation', id);
      return { donation: donationView(donationRow(id), user, null, true) };
    });
  });

  // ---------- foundations ----------
  app.get('/foundations', async (req) => {
    const user = authUser(req);
    let rows = db.prepare("SELECT * FROM users WHERE role='foundation' ORDER BY org_name").all();
    if (user.role !== 'admin') rows = rows.filter((f) => f.verified);
    const { q, need } = req.query;
    if (q) {
      const n = String(q).toLowerCase();
      rows = rows.filter((f) => `${f.org_name} ${f.about} ${f.address}`.toLowerCase().includes(n));
    }
    if (need) rows = rows.filter((f) => parseJson(f.needs, []).includes(need));
    return { items: rows.map(foundationView) };
  });

  app.get('/foundations/:id', async (req) => {
    const user = authUser(req);
    const f = db.prepare("SELECT * FROM users WHERE id=? AND role='foundation'").get(Number(req.params.id) || 0);
    if (!f || (!f.verified && user.role !== 'admin' && user.id !== f.id)) throw new ApiError(404, 'NOT_FOUND', 'Foundation not found');
    return { foundation: foundationView(f) };
  });

  app.get('/foundation/dashboard', async (req) => {
    const user = authRole(req, 'foundation');
    sweepDonations();
    const loc = getLoc(req.query) || foundationLoc(user);
    const active = donationRows("WHERE d.claimed_by=? AND d.status IN ('claimed','picked_up') ORDER BY d.expires_at", user.id)
      .map((d) => donationView(d, user, loc));
    let nearby = donationRows("WHERE d.status='available' ORDER BY d.expires_at").map((d) => donationView(d, user, loc));
    if (loc) nearby = nearby.filter((d) => d.distanceKm <= CONFIG.foundationAlertRadiusKm);
    return {
      stats: foundationStats(user.id), activeClaims: active, nearbyAvailable: nearby.slice(0, 20),
      needs: parseJson(user.needs, []),
    };
  });

  app.get('/me/donations', async (req) => {
    const user = authUser(req);
    sweepDonations();
    return { items: donationsByDonor(user, getLoc(req.query)) };
  });
}
