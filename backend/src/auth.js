import { db } from './db.js';
import { ApiError } from './util.js';

/** Resolves the signed-in user from the bearer token (401 otherwise). */
export function authUser(req) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (!token) throw new ApiError(401, 'UNAUTHENTICATED', 'Please sign in');
  const row = db.prepare('SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token=?').get(token);
  if (!row) throw new ApiError(401, 'UNAUTHENTICATED', 'Session expired. Please sign in again');
  return row;
}

const ROLE_WORD = { admin: 'authority officers', neta: 'elected leaders', foundation: 'foundations', citizen: 'citizens' };

/** Signs in and checks the role. Anything else -> 403 FORBIDDEN. */
export function authRole(req, ...roles) {
  const user = authUser(req);
  if (!roles.includes(user.role)) {
    throw new ApiError(403, 'FORBIDDEN', `This is only available to ${roles.map((r) => ROLE_WORD[r]).join(' and ')}`);
  }
  return user;
}
