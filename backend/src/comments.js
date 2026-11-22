// Comments, likes and shares shared by issues, gatherings and donations.
import { db } from './db.js';
import { now, ApiError } from './util.js';
import { authUser } from './auth.js';
import { cleanMedia, parseJson, userRef, commentCount } from './common.js';
import { issueRow, issueView, award, notify } from './logic.js';
import { gatheringRow, gatheringView } from './gatherings.js';
import { donationRow, donationView } from './donations.js';
import { POINTS } from './config.js';

const TARGETS = {
  issue: {
    path: 'issues', label: 'Issue', get: issueRow, owner: (r) => r.reporter_id, table: 'issues',
    view: (r, u) => issueView(r, u), reload: (id) => issueRow(id),
  },
  gathering: {
    path: 'gatherings', label: 'Gathering', get: gatheringRow, owner: (r) => r.organizer_id, table: 'gatherings',
    view: (r, u) => gatheringView(r, u), reload: (id) => gatheringRow(id),
  },
  donation: {
    path: 'donations', label: 'Donation', get: donationRow, owner: (r) => r.donor_id, table: 'donations',
    view: (r, u) => donationView(r, u), reload: (id) => donationRow(id),
  },
};

const commentView = (c) => ({
  id: c.id, body: c.body, author: userRef(c.user_id), createdAt: c.created_at, media: parseJson(c.media, []),
});

export function registerCommentRoutes(app) {
  for (const [type, T] of Object.entries(TARGETS)) {
    const target = (req) => {
      const row = T.get(Number(req.params.id) || 0);
      if (!row) throw new ApiError(404, 'NOT_FOUND', `${T.label} not found`);
      return row;
    };

    app.get(`/${T.path}/:id/comments`, async (req) => {
      authUser(req);
      const row = target(req);
      const items = db.prepare('SELECT * FROM comments WHERE target_type=? AND target_id=? ORDER BY created_at, id').all(type, row.id);
      return { items: items.map(commentView) };
    });

    app.post(`/${T.path}/:id/comments`, async (req, reply) => {
      const user = authUser(req);
      const row = target(req);
      const body = String(req.body?.body ?? '').trim();
      if (!body) throw new ApiError(400, 'BAD_COMMENT', 'Write something before posting');
      if (body.length > 1000) throw new ApiError(400, 'BAD_COMMENT', 'Comments can be up to 1000 characters');
      const media = cleanMedia(req.body?.media, 4);
      const info = db.prepare('INSERT INTO comments (target_type,target_id,user_id,body,media,created_at) VALUES (?,?,?,?,?,?)')
        .run(type, row.id, user.id, body, JSON.stringify(media), now());
      const comment = db.prepare('SELECT * FROM comments WHERE id=?').get(Number(info.lastInsertRowid));
      const owner = T.owner(row);
      if (owner !== user.id) {
        const snippet = body.length > 80 ? `${body.slice(0, 77)}...` : body;
        notify(owner, 'comment', `${user.org_name || user.name} commented`, snippet, type === 'issue' ? row.id : null, type, row.id);
      }
      const rewards = user.role === 'citizen' ? award(user.id, POINTS.comment, ['Joined the conversation']) : null;
      reply.status(201);
      return { comment: commentView(comment), commentCount: commentCount(type, row.id), rewards };
    });

    app.post(`/${T.path}/:id/like`, async (req) => {
      const user = authUser(req);
      const row = target(req);
      db.prepare('INSERT OR IGNORE INTO likes (target_type,target_id,user_id,created_at) VALUES (?,?,?,?)').run(type, row.id, user.id, now());
      return { [type]: T.view(T.reload(row.id), user) };
    });

    app.delete(`/${T.path}/:id/like`, async (req) => {
      const user = authUser(req);
      const row = target(req);
      db.prepare('DELETE FROM likes WHERE target_type=? AND target_id=? AND user_id=?').run(type, row.id, user.id);
      return { [type]: T.view(T.reload(row.id), user) };
    });

    app.post(`/${T.path}/:id/share`, async (req) => {
      const user = authUser(req);
      const row = target(req);
      db.prepare(`UPDATE ${T.table} SET share_count = share_count + 1 WHERE id=?`).run(row.id);
      const v = T.view(T.reload(row.id), user);
      return { shareCount: v.shareCount, shareText: v.shareText, publicUrl: v.publicUrl };
    });
  }
}
