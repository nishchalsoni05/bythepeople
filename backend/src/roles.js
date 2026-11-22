// Role portals: authority (admin) and elected leader (neta), plus foundation verification.
import { db, tx } from './db.js';
import { CATEGORIES } from './config.js';
import { now, ApiError } from './util.js';
import { authRole } from './auth.js';
import { cleanMedia, getLoc } from './common.js';
import {
  issueRows, issueRow, issueView, addHistory, notify, descendantIds, netaView,
} from './logic.js';
import { gatheringRows, gatheringView, statusOf } from './gatherings.js';
import { foundationView } from './donations.js';

const round = (n, d = 1) => Math.round(n * 10 ** d) / 10 ** d;

/** One mutually exclusive state per issue, from the authority's point of view. */
export function adminBucket(r) {
  if (r.status === 'closed') return 'closed';
  if (r.status === 'pending_verification') return 'pending_verification';
  if (r.status === 'in_progress') return 'in_progress';
  return r.authority_status === 'acknowledged' ? 'acknowledged' : 'open';
}

const BUCKET_ALIAS = { inProgress: 'in_progress', pendingVerification: 'pending_verification' };

function cityRows(admin) {
  return admin.city_id ? issueRows('WHERE i.city_id=?', admin.city_id) : issueRows();
}

function requireInJurisdiction(admin, issue) {
  if (admin.city_id && issue.city_id !== admin.city_id) {
    throw new ApiError(403, 'FORBIDDEN', 'This issue is outside your city. Only the local authority can update it.');
  }
}

const viewOf = (r, user, loc) => issueView(r, user, loc);
const topByEngagement = (items) => items.sort((a, b) => b.engagement - a.engagement || b.createdAt - a.createdAt);

function jurisdictionRows(neta) {
  if (!neta.politician_id) throw new ApiError(403, 'FORBIDDEN', 'Your account is not linked to an elected position yet');
  const ids = descendantIds(neta.politician_id);
  return { ids, rows: issueRows(`WHERE i.politician_id IN (${ids.map(() => '?').join(',')})`, ...ids) };
}

export function registerRoleRoutes(app) {
  // ---------- authority portal ----------
  app.get('/admin/issues', async (req) => {
    const admin = authRole(req, 'admin');
    const q = req.query;
    const loc = getLoc(q);
    let rows = cityRows(admin);
    if (q.status) {
      const want = BUCKET_ALIAS[q.status] || q.status;
      if (!['open', 'acknowledged', 'in_progress', 'pending_verification', 'closed'].includes(want)) {
        throw new ApiError(400, 'BAD_FILTER', 'Unknown status filter');
      }
      rows = rows.filter((r) => adminBucket(r) === want);
    }
    if (q.escalated === '1' || q.escalated === 'true') rows = rows.filter((r) => r.escalated);
    if (q.category) rows = rows.filter((r) => r.category === q.category);
    if (q.q) {
      const n = String(q.q).toLowerCase();
      rows = rows.filter((r) => r.title.toLowerCase().includes(n) || (r.description || '').toLowerCase().includes(n) || (r.address || '').toLowerCase().includes(n));
    }
    const items = rows.map((r) => viewOf(r, admin, loc));
    const sort = q.sort;
    if (sort === 'new') items.sort((a, b) => b.createdAt - a.createdAt);
    else if (sort === 'oldest') items.sort((a, b) => a.createdAt - b.createdAt);
    else if (sort === 'top') topByEngagement(items);
    else items.sort((a, b) => Number(b.escalated) - Number(a.escalated) || b.engagement - a.engagement || b.createdAt - a.createdAt);
    return { items };
  });

  app.get('/admin/dashboard', async (req) => {
    const admin = authRole(req, 'admin');
    const rows = cityRows(admin);
    const counts = { open: 0, acknowledged: 0, inProgress: 0, pendingVerification: 0, closed: 0, escalated: 0 };
    let hours = 0; let closedN = 0;
    const byCat = new Map(Object.keys(CATEGORIES).map((k) => [k, { category: k, label: CATEGORIES[k].label, count: 0, open: 0 }]));
    for (const r of rows) {
      const b = adminBucket(r);
      if (b === 'in_progress') counts.inProgress++;
      else if (b === 'pending_verification') counts.pendingVerification++;
      else counts[b]++;
      if (r.escalated && r.status !== 'closed') counts.escalated++;
      if (r.status === 'closed' && r.closed_at) { hours += (r.closed_at - r.created_at) / 3600000; closedN++; }
      const c = byCat.get(r.category) || byCat.get('other');
      c.count++;
      if (r.status !== 'closed') c.open++;
    }
    const topIssues = topByEngagement(rows.filter((r) => r.status !== 'closed').map((r) => viewOf(r, admin))).slice(0, 5);
    const ids = new Set(rows.map((r) => r.id));
    const recent = db.prepare(`SELECT h.id,h.issue_id,h.status,h.note,h.created_at,h.kind,h.actor_role,h.media,i.title,u.name AS user_name
      FROM status_history h JOIN issues i ON i.id=h.issue_id LEFT JOIN users u ON u.id=h.user_id
      ${admin.city_id ? 'WHERE i.city_id=?' : ''} ORDER BY h.created_at DESC, h.id DESC LIMIT 12`).all(...(admin.city_id ? [admin.city_id] : []))
      .filter((h) => ids.has(h.issue_id))
      .map((h) => ({
        id: h.id, issueId: h.issue_id, issueTitle: h.title, status: h.status, note: h.note, createdAt: h.created_at,
        kind: h.kind, actorRole: h.actor_role, userName: h.user_name, media: JSON.parse(h.media || '[]'),
      }));
    return {
      counts,
      avgResolutionHours: closedN ? round(hours / closedN) : 0,
      byCategory: [...byCat.values()].filter((c) => c.count > 0).sort((a, b) => b.count - a.count),
      topIssues,
      pendingFoundations: db.prepare("SELECT COUNT(*) c FROM users WHERE role='foundation' AND verify_status='pending'").get().c,
      recent,
    };
  });

  app.post('/issues/:id/authority-update', async (req) => {
    const admin = authRole(req, 'admin');
    const id = Number(req.params.id) || 0;
    const b = req.body || {};
    const status = b.status;
    if (!['acknowledged', 'in_progress', 'resolved'].includes(status)) {
      throw new ApiError(400, 'BAD_STATUS', 'status must be acknowledged, in_progress or resolved');
    }
    const media = cleanMedia(b.media);
    const note = String(b.note || '').trim();
    const assigned = b.assignedTo === undefined || b.assignedTo === null ? undefined : String(b.assignedTo).trim().slice(0, 120);
    return tx(() => {
      const issue = issueRow(id);
      if (!issue) throw new ApiError(404, 'NOT_FOUND', 'Issue not found');
      requireInJurisdiction(admin, issue);
      if (issue.status === 'closed') throw new ApiError(409, 'CLOSED', 'This issue is already closed');
      if (issue.status === 'pending_verification') {
        throw new ApiError(409, 'AWAITING_VERIFICATION', 'This issue is already marked fixed and is waiting for neighbours to verify it');
      }
      if (status === 'acknowledged' && issue.authority_status !== 'open') {
        throw new ApiError(409, 'BAD_STATE', 'This issue has already been acknowledged');
      }
      if (status === 'resolved') {
        if (!note) throw new ApiError(400, 'NOTE_REQUIRED', 'Describe what was done before marking it resolved');
        if (!media.length) throw new ApiError(400, 'PROOF_REQUIRED', 'Attach at least one photo or video as proof of the fix');
      }
      const dept = issueView(issue, null).authority.department;
      let timelineStatus = issue.status;
      let text;
      if (status === 'acknowledged') {
        db.prepare("UPDATE issues SET authority_status='acknowledged' WHERE id=?").run(id);
        text = note || `Acknowledged by ${dept}`;
      } else if (status === 'in_progress') {
        db.prepare("UPDATE issues SET status='in_progress', authority_status='in_progress' WHERE id=?").run(id);
        timelineStatus = 'in_progress';
        text = note || `Work has started (${dept})`;
      } else {
        db.prepare("UPDATE issues SET status='pending_verification', authority_status='resolved', resolved_at=?, resolution_note=? WHERE id=?").run(now(), note, id);
        timelineStatus = 'pending_verification';
        text = `Marked resolved by ${admin.department_name || 'the authority'}: ${note}`;
      }
      if (assigned !== undefined) db.prepare('UPDATE issues SET assigned_to=? WHERE id=?').run(assigned || null, id);
      if (assigned && status !== 'resolved') text += ` (assigned to ${assigned})`;
      addHistory(id, timelineStatus, text, admin.id, { kind: 'authority', media });
      const audience = new Set([issue.reporter_id, ...db.prepare('SELECT user_id FROM supports WHERE issue_id=?').all(id).map((r) => r.user_id)]);
      audience.delete(admin.id);
      const titles = {
        acknowledged: ['Authority acknowledged your issue', `${admin.department_name || 'The authority'} has seen "${issue.title}"`],
        in_progress: ['Work has started', `${admin.department_name || 'The authority'} is working on "${issue.title}"`],
        resolved: ['Authority says it is fixed', `Please verify "${issue.title}" if you are nearby`],
      }[status];
      for (const uid of audience) notify(uid, 'authority_update', titles[0], titles[1], id);
      return { issue: issueView(issueRow(id), admin, null, true) };
    });
  });

  app.get('/admin/foundations', async (req) => {
    authRole(req, 'admin');
    const st = req.query.status || 'pending';
    if (!['pending', 'verified', 'all'].includes(st)) throw new ApiError(400, 'BAD_FILTER', 'status must be pending, verified or all');
    let rows = db.prepare("SELECT * FROM users WHERE role='foundation' ORDER BY created_at DESC, id DESC").all();
    if (st === 'pending') rows = rows.filter((f) => f.verify_status === 'pending');
    else if (st === 'verified') rows = rows.filter((f) => f.verified);
    return { items: rows.map(foundationView) };
  });

  app.post('/admin/foundations/:id/verify', async (req) => {
    const admin = authRole(req, 'admin');
    const f = db.prepare("SELECT * FROM users WHERE id=? AND role='foundation'").get(Number(req.params.id) || 0);
    if (!f) throw new ApiError(404, 'NOT_FOUND', 'Foundation not found');
    if (typeof req.body?.approve !== 'boolean') throw new ApiError(400, 'BAD_REQUEST', 'approve must be true or false');
    const approve = req.body.approve;
    const note = String(req.body.note || '').trim();
    db.prepare('UPDATE users SET verified=?, verify_status=?, verify_note=? WHERE id=?')
      .run(approve ? 1 : 0, approve ? 'verified' : 'rejected', note || null, f.id);
    if (approve) {
      notify(f.id, 'foundation_verified', 'You are verified', `${admin.department_name || 'The authority'} verified ${f.org_name || f.name}. You can now claim donations.`);
    } else {
      notify(f.id, 'foundation_verified', 'Verification declined', note || 'Your foundation could not be verified. Check your registration number and try again.');
    }
    return { foundation: foundationView(db.prepare('SELECT * FROM users WHERE id=?').get(f.id)) };
  });

  // ---------- neta portal ----------
  app.get('/neta/feed', async (req) => {
    const neta = authRole(req, 'neta');
    const q = req.query;
    let { rows } = jurisdictionRows(neta);
    if (q.status) {
      const want = q.status === 'resolved' ? 'closed' : BUCKET_ALIAS[q.status] || q.status;
      rows = rows.filter((r) => r.status === want);
    }
    if (q.escalated === '1') rows = rows.filter((r) => r.escalated);
    const items = rows.map((r) => viewOf(r, neta, getLoc(q)));
    if (q.sort === 'new') items.sort((a, b) => b.createdAt - a.createdAt);
    else topByEngagement(items);
    return { items };
  });

  app.get('/neta/dashboard', async (req) => {
    const neta = authRole(req, 'neta');
    const { rows } = jurisdictionRows(neta);
    const counts = { open: 0, inProgress: 0, resolved: 0, escalated: 0 };
    for (const r of rows) {
      if (r.status === 'closed') counts.resolved++;
      else if (r.status === 'in_progress' || r.status === 'pending_verification') counts.inProgress++;
      else counts.open++;
      if (r.escalated && r.status !== 'closed') counts.escalated++;
    }
    const pol = db.prepare('SELECT * FROM politicians WHERE id=?').get(neta.politician_id);
    const city = pol.city_id ? db.prepare('SELECT * FROM areas WHERE id=?').get(pol.city_id) : null;
    const upcoming = gatheringRows('ORDER BY g.start_at')
      .filter((g) => ['upcoming', 'ongoing'].includes(statusOf(g)))
      .filter((g) => g.organizer_id === neta.id || !city || (Math.abs(g.lat - city.lat) < 0.5 && Math.abs(g.lng - city.lng) < 0.5))
      .slice(0, 5).map((g) => gatheringView(g, neta));
    return {
      politician: netaView(pol),
      counts,
      resolutionRate: rows.length ? round(counts.resolved / rows.length, 3) : 0,
      topIssues: topByEngagement(rows.filter((r) => r.status !== 'closed').map((r) => viewOf(r, neta))).slice(0, 5),
      upcomingGatherings: upcoming,
    };
  });

  const jurisdictionIssue = (neta, id) => {
    const issue = issueRow(id);
    if (!issue) throw new ApiError(404, 'NOT_FOUND', 'Issue not found');
    const { ids } = jurisdictionRows(neta);
    if (!ids.includes(issue.politician_id)) {
      throw new ApiError(403, 'OUT_OF_JURISDICTION', 'This issue belongs to another representative\'s area');
    }
    return issue;
  };

  app.post('/issues/:id/escalate', async (req) => {
    const neta = authRole(req, 'neta');
    const id = Number(req.params.id) || 0;
    const note = String(req.body?.note || '').trim();
    if (!note) throw new ApiError(400, 'NOTE_REQUIRED', 'Add a short note explaining why this needs the authority\'s attention');
    return tx(() => {
      const issue = jurisdictionIssue(neta, id);
      if (issue.status === 'closed') throw new ApiError(409, 'CLOSED', 'This issue is already closed');
      if (issue.escalated) throw new ApiError(409, 'ALREADY', 'This issue is already escalated');
      db.prepare('UPDATE issues SET escalated=1, escalated_by=?, escalation_note=? WHERE id=?').run(neta.id, note, id);
      addHistory(id, issue.status, `Escalated to admin portal by ${neta.name}: ${note}`, neta.id, { kind: 'neta' });
      let admins = db.prepare("SELECT id FROM users WHERE role='admin' AND (city_id IS NULL OR city_id=?)").all(issue.city_id);
      if (!admins.length) admins = db.prepare("SELECT id FROM users WHERE role='admin'").all();
      for (const a of admins) notify(a.id, 'escalated', 'Escalated by an elected leader', `${neta.name} escalated "${issue.title}"`, id);
      notify(issue.reporter_id, 'escalated', 'Your leader escalated your issue', `${neta.name} escalated "${issue.title}" to the authority`, id);
      return { issue: issueView(issueRow(id), neta, null, true) };
    });
  });

  app.delete('/issues/:id/escalate', async (req) => {
    const neta = authRole(req, 'neta');
    const id = Number(req.params.id) || 0;
    return tx(() => {
      const issue = jurisdictionIssue(neta, id);
      if (!issue.escalated) throw new ApiError(409, 'NOT_ESCALATED', 'This issue is not escalated');
      db.prepare('UPDATE issues SET escalated=0, escalated_by=NULL, escalation_note=NULL WHERE id=?').run(id);
      addHistory(id, issue.status, `Escalation withdrawn by ${neta.name}`, neta.id, { kind: 'neta' });
      return { issue: issueView(issueRow(id), neta, null, true) };
    });
  });

  app.post('/issues/:id/neta-response', async (req) => {
    const neta = authRole(req, 'neta');
    const id = Number(req.params.id) || 0;
    const note = String(req.body?.note || '').trim();
    if (note.length < 3) throw new ApiError(400, 'NOTE_REQUIRED', 'Write your response for the public timeline');
    return tx(() => {
      const issue = jurisdictionIssue(neta, id);
      addHistory(id, issue.status, `${neta.name}: ${note}`, neta.id, { kind: 'neta' });
      notify(issue.reporter_id, 'authority_update', 'Your leader responded', `${neta.name} responded on "${issue.title}"`, id);
      return { issue: issueView(issueRow(id), neta, null, true) };
    });
  });
}
