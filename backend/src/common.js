// Small helpers shared by the v3 modules (roles, gatherings, donations, comments, media, public).
import { db } from './db.js';
import { ApiError } from './util.js';

export const IST_OFFSET_MS = 5.5 * 3600000;

export const parseJson = (s, fallback) => {
  try { const v = JSON.parse(s); return v ?? fallback; } catch { return fallback; }
};

/** Validates media[] from a request body: only paths returned by POST /media are accepted. */
export function cleanMedia(input, max = 10) {
  if (input === undefined || input === null) return [];
  if (!Array.isArray(input)) throw new ApiError(400, 'BAD_MEDIA', 'media must be a list of uploaded file paths');
  if (input.length > max) throw new ApiError(400, 'BAD_MEDIA', `You can attach up to ${max} photos or videos`);
  for (const m of input) {
    if (typeof m !== 'string' || !/^\/uploads\/[A-Za-z0-9._-]+\.(jpg|jpeg|png|webp|mp4|mov)$/i.test(m)) {
      throw new ApiError(400, 'BAD_MEDIA', 'Attach photos or videos using the path returned by /media');
    }
  }
  return input;
}

export const mediaOf = (s) => parseJson(s, []);

export const publicBase = () => (process.env.PUBLIC_BASE_URL || `http://localhost:${process.env.PORT || 3000}`).replace(/\/$/, '');
export const publicUrl = (type, id) => `${publicBase()}/p/${type}s/${id}`;

export function userRefFromRow(u) {
  if (!u) return null;
  const ref = { id: u.id, name: u.name, hue: u.hue, role: u.role || 'citizen' };
  if (u.org_name) ref.orgName = u.org_name;
  if (u.role === 'foundation') ref.verified = !!u.verified;
  if (u.avatar_url) ref.avatarUrl = u.avatar_url;
  return ref;
}

export const userRef = (id) => (id == null ? null : userRefFromRow(db.prepare('SELECT * FROM users WHERE id=?').get(id)));

export const likeCount = (type, id) => db.prepare('SELECT COUNT(*) c FROM likes WHERE target_type=? AND target_id=?').get(type, id).c;
export const commentCount = (type, id) => db.prepare('SELECT COUNT(*) c FROM comments WHERE target_type=? AND target_id=?').get(type, id).c;
export const likedBy = (type, id, user) =>
  !!user && !!db.prepare('SELECT 1 x FROM likes WHERE target_type=? AND target_id=? AND user_id=?').get(type, id, user.id);

export function pageNumber(v, def, max) {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? Math.min(n, max) : def;
}

export const getLoc = (q) => {
  const la = Number(q.lat); const ln = Number(q.lng);
  return q.lat !== undefined && q.lng !== undefined && q.lat !== '' && q.lng !== '' && Number.isFinite(la) && Number.isFinite(ln)
    ? { lat: la, lng: ln } : null;
};
