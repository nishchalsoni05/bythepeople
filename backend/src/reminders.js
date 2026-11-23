// Calendar reminders: for me, for space collaborators, or sent to a collaborator.
import { db } from './db.js';
import { now, ApiError, num } from './util.js';
import { authUser } from './auth.js';
import { userRef } from './common.js';
import { notify } from './logic.js';

const SCOPES = ['me', 'space', 'collaborator'];

export function reminderView(r, user) {
  return {
    id: r.id,
    title: r.title,
    scope: r.scope,
    recipient: r.recipient_id ? userRef(r.recipient_id) : null,
    remindAt: r.remind_at,
    refType: r.ref_type ?? null,
    refId: r.ref_id ?? null,
    done: !!r.done,
    mine: r.user_id === user.id,
  };
}

export function registerReminderRoutes(app) {
  app.get('/reminders', async (req) => {
    const user = authUser(req);
    const rows = db.prepare(`SELECT * FROM reminders
      WHERE user_id=? OR (scope='collaborator' AND recipient_id=?)
      ORDER BY remind_at ASC, id ASC`).all(user.id, user.id);
    return { items: rows.map((r) => reminderView(r, user)) };
  });

  app.post('/reminders', async (req, reply) => {
    const user = authUser(req);
    const b = req.body || {};
    const title = String(b.title || '').trim();
    if (!title) throw new ApiError(400, 'BAD_TITLE', 'Give the reminder a title');
    if (!SCOPES.includes(b.scope)) throw new ApiError(400, 'BAD_SCOPE', 'Scope must be me, space or collaborator');
    const remindAt = num(b.remindAt);
    if (!Number.isFinite(remindAt)) throw new ApiError(400, 'BAD_REMIND_AT', 'Pick when to remind (a unix time in milliseconds)');
    let recipientId = null;
    if (b.scope === 'collaborator') {
      if (b.recipientId === undefined || b.recipientId === null || b.recipientId === '') {
        throw new ApiError(400, 'BAD_REQUEST', 'Pick the collaborator to remind');
      }
      recipientId = Number(b.recipientId);
      const exists = Number.isInteger(recipientId) && db.prepare('SELECT 1 x FROM users WHERE id=?').get(recipientId);
      if (!exists) throw new ApiError(404, 'NOT_FOUND', 'Collaborator not found');
      if (recipientId === user.id) throw new ApiError(400, 'BAD_RECIPIENT', 'Pick someone other than yourself');
    }
    const refType = b.refType ? String(b.refType) : null;
    const refId = b.refId !== undefined && b.refId !== null && b.refId !== '' && Number.isFinite(num(b.refId)) ? Number(b.refId) : null;
    const info = db.prepare(`INSERT INTO reminders (user_id,title,scope,recipient_id,remind_at,ref_type,ref_id,done,created_at)
      VALUES (?,?,?,?,?,?,?,0,?)`).run(user.id, title, b.scope, recipientId, remindAt, refType, refId, now());
    const id = Number(info.lastInsertRowid);
    if (recipientId) {
      notify(recipientId, 'reminder', `Reminder from ${user.name}`, title, null, 'reminder', id);
    }
    reply.status(201);
    return { reminder: reminderView(db.prepare('SELECT * FROM reminders WHERE id=?').get(id), user) };
  });

  app.delete('/reminders/:id', async (req) => {
    const user = authUser(req);
    const id = Number(req.params.id) || 0;
    const r = db.prepare('SELECT * FROM reminders WHERE id=?').get(id);
    if (!r) throw new ApiError(404, 'NOT_FOUND', 'Reminder not found');
    if (r.user_id !== user.id) throw new ApiError(403, 'FORBIDDEN', 'Only the person who set this reminder can delete it');
    db.prepare('DELETE FROM reminders WHERE id=?').run(id);
    return { ok: true };
  });
}
