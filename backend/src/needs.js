// Foundation needs: a verified foundation posts what it needs, donors pledge to help.
import { db } from './db.js';
import { DONATION_KINDS, NEED_URGENCY } from './config.js';
import { now, ApiError } from './util.js';
import { authUser, authRole } from './auth.js';
import { notify } from './logic.js';

const hasKind = (k) => Object.prototype.hasOwnProperty.call(DONATION_KINDS, k);
const NEED_SQL = `SELECT n.*, f.name AS f_name, f.org_name AS f_org, f.verified AS f_verified
  FROM needs n JOIN users f ON f.id=n.foundation_id`;

export const needRow = (id) => db.prepare(`${NEED_SQL} WHERE n.id=?`).get(id);

export function needView(n, user) {
  const pledgeCount = db.prepare('SELECT COUNT(*) c FROM need_pledges WHERE need_id=?').get(n.id).c;
  const pledgedByMe = !!user && !!db.prepare('SELECT 1 x FROM need_pledges WHERE need_id=? AND user_id=?').get(n.id, user.id);
  const pledgedQty = (n.pledged_qty || 0) + db.prepare('SELECT COALESCE(SUM(qty),0) c FROM need_pledges WHERE need_id=?').get(n.id).c;
  const target = n.target_qty || 0;
  return {
    id: n.id,
    foundation: { id: n.foundation_id, name: n.f_org || n.f_name, orgName: n.f_org || n.f_name, verified: !!n.f_verified },
    kind: n.kind,
    kindLabel: DONATION_KINDS[n.kind] || 'Other',
    title: n.title,
    quantity: n.quantity || '',
    description: n.description || '',
    urgency: n.urgency || 'normal',
    unit: n.unit || '',
    targetQty: target,
    pledgedQty: pledgedQty,
    progress: target > 0 ? Math.min(1, pledgedQty / target) : 0,
    deadlineAt: n.deadline_at ?? null,
    status: n.status,
    pledgeCount,
    pledgedByMe,
    createdAt: n.created_at,
  };
}

const mustNeed = (id) => {
  const n = needRow(id);
  if (!n) throw new ApiError(404, 'NOT_FOUND', 'Need not found');
  return n;
};

export function registerNeedRoutes(app) {
  app.get('/needs', async (req) => {
    const user = authUser(req);
    const status = req.query.status || 'open';
    if (!['open', 'closed', 'all'].includes(status)) throw new ApiError(400, 'BAD_FILTER', 'status must be open, closed or all');
    const where = status === 'all' ? '' : status === 'open' ? "WHERE n.status='open'" : "WHERE n.status IN ('closed','fulfilled')";
    const rows = db.prepare(`${NEED_SQL} ${where} ORDER BY n.created_at DESC, n.id DESC`).all();
    return { items: rows.map((n) => needView(n, user)) };
  });

  app.post('/needs', async (req, reply) => {
    const user = authRole(req, 'foundation');
    if (!user.verified) throw new ApiError(403, 'NOT_VERIFIED', 'Your foundation is awaiting verification. You can post needs once it is approved.');
    const b = req.body || {};
    const kind = b.kind;
    if (typeof kind !== 'string' || !hasKind(kind)) {
      throw new ApiError(400, 'BAD_KIND', `Pick what you need: ${Object.keys(DONATION_KINDS).join(', ')}`);
    }
    const title = String(b.title || '').trim();
    if (title.length < 3) throw new ApiError(400, 'BAD_TITLE', 'Give the need a short title (3+ characters)');
    const quantity = String(b.quantity || '').trim().slice(0, 100);
    let deadlineAt = null;
    if (b.deadlineAt !== undefined && b.deadlineAt !== null && b.deadlineAt !== '') {
      deadlineAt = Number(b.deadlineAt);
      if (!Number.isFinite(deadlineAt) || deadlineAt <= now()) throw new ApiError(400, 'BAD_DEADLINE', 'The deadline must be a time in the future');
    }
    const urgency = b.urgency === undefined || b.urgency === null || b.urgency === '' ? 'normal' : String(b.urgency);
    if (!NEED_URGENCY.includes(urgency)) throw new ApiError(400, 'BAD_URGENCY', `urgency must be one of ${NEED_URGENCY.join(', ')}`);
    const targetQty = Math.max(0, Math.min(1000000, Math.floor(Number(b.targetQty) || 0)));
    const description = String(b.description || '').trim().slice(0, 500);
    const unit = String(b.unit || '').trim().slice(0, 30);
    const info = db.prepare(`INSERT INTO needs (foundation_id,kind,title,quantity,deadline_at,status,created_at,urgency,description,target_qty,unit)
      VALUES (?,?,?,?,?,'open',?,?,?,?,?)`).run(user.id, kind, title, quantity, deadlineAt, now(), urgency, description, targetQty, unit);
    reply.status(201);
    return { need: needView(needRow(Number(info.lastInsertRowid)), user) };
  });

  app.post('/needs/:id/pledge', async (req) => {
    const user = authUser(req);
    const n = mustNeed(Number(req.params.id) || 0);
    if (n.foundation_id === user.id) throw new ApiError(409, 'OWN_NEED', 'You cannot pledge to your own need');
    if (n.status !== 'open') throw new ApiError(409, 'NOT_OPEN', 'This need is no longer open');
    const note = req.body?.note ? String(req.body.note).trim().slice(0, 300) : null;
    const qty = Math.max(0, Math.min(1000000, Math.floor(Number(req.body?.qty) || 0)));
    const r = db.prepare('INSERT OR IGNORE INTO need_pledges (need_id,user_id,note,created_at,qty) VALUES (?,?,?,?,?)').run(n.id, user.id, note, now(), qty);
    if (r.changes) {
      notify(n.foundation_id, 'need_pledge', 'Someone pledged to your need',
        `${user.name} pledged to help with "${n.title}"`, null, 'need', n.id);
    }
    return { need: needView(needRow(n.id), user) };
  });

  app.delete('/needs/:id/pledge', async (req) => {
    const user = authUser(req);
    const n = mustNeed(Number(req.params.id) || 0);
    db.prepare('DELETE FROM need_pledges WHERE need_id=? AND user_id=?').run(n.id, user.id);
    return { need: needView(needRow(n.id), user) };
  });

  app.post('/needs/:id/close', async (req) => {
    const user = authUser(req);
    const n = mustNeed(Number(req.params.id) || 0);
    if (n.foundation_id !== user.id) throw new ApiError(403, 'NOT_OWNER', 'Only the foundation that posted this need can close it');
    db.prepare("UPDATE needs SET status='closed' WHERE id=?").run(n.id);
    return { need: needView(needRow(n.id), user) };
  });
}
