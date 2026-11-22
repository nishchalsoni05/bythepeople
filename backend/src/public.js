// Public, no-auth HTML status pages (link previews for WhatsApp / X).
import { ApiError } from './util.js';
import { issueRow, issueView } from './logic.js';
import { gatheringRow, gatheringView } from './gatherings.js';
import { donationRow, donationView } from './donations.js';
import { publicBase } from './common.js';

const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const when = (ms) => new Date(ms).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', dateStyle: 'medium', timeStyle: 'short' });

function page({ title, desc, image, body }) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)} | By the People</title>
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(desc)}"><meta property="og:site_name" content="By the People">
${image ? `<meta property="og:image" content="${esc(publicBase() + image)}">` : ''}
<style>body{font:16px/1.5 system-ui,sans-serif;margin:0;background:#f6f4ef;color:#1d2a24}main{max-width:560px;margin:0 auto;padding:20px}
.brand{font-weight:700;color:#0f6b4f;letter-spacing:.02em;margin-bottom:12px}.card{background:#fff;border-radius:16px;padding:18px;box-shadow:0 2px 10px #0001}
h1{font-size:22px;margin:.2em 0}.pill{display:inline-block;background:#0f6b4f;color:#fff;border-radius:99px;padding:2px 12px;font-size:13px}
.muted{color:#5d6b64;font-size:14px}ul{padding-left:18px}img{max-width:100%;border-radius:12px;margin:8px 0}li{margin:6px 0}</style></head>
<body><main><div class="brand">By the People</div><div class="card">${body}</div>
<p class="muted">Open the By the People app to support, join or help.</p></main></body></html>`;
}

const imgs = (media) => (media || []).filter((m) => /\.(jpe?g|png|webp)$/i.test(m)).slice(0, 3).map((m) => `<img src="${esc(m)}" alt="">`).join('');

function issuePage(r) {
  const v = issueView(r, null, null, true);
  const tl = v.timeline.map((t) => `<li><b>${esc(t.status.replace('_', ' '))}</b> ${esc(t.note || '')} <span class="muted">${esc(when(t.createdAt))}</span></li>`).join('');
  return page({
    title: v.title, desc: `${v.authorityStatus.replace('_', ' ')} | ${v.supportCount} neighbours support this | ${v.authority.name}`, image: v.media[0],
    body: `<span class="pill">${esc(v.authorityStatus.replace('_', ' '))}</span><h1>${esc(v.title)}</h1>
<p>${esc(v.description)}</p>${imgs(v.media)}
<p class="muted">${esc(v.categoryLabel)} | ${esc(v.address || v.area.city?.name || '')}</p>
<p><b>Responsible authority:</b> ${esc(v.authority.name)} (${esc(v.authority.department)}) ${esc(v.authority.handle)}</p>
<p><b>${v.supportCount}</b> neighbours support this${v.escalated ? ' | escalated by an elected leader' : ''}</p><h3>Timeline</h3><ul>${tl}</ul>`,
  });
}

function gatheringPage(g) {
  const v = gatheringView(g, null, null, true);
  return page({
    title: v.title, desc: `${v.typeLabel} | ${when(v.startAt)} | ${v.goingCount} going`, image: v.media[0],
    body: `<span class="pill">${esc(v.status)}</span><h1>${esc(v.title)}</h1><p>${esc(v.description)}</p>${imgs(v.media)}
<p><b>${esc(v.typeLabel)}</b> | ${esc(when(v.startAt))}</p><p>${esc(v.address || '')}</p>
<p>Organised by ${esc(v.organizer.name)}${v.club ? ` | ${esc(v.club.name)}` : ''}</p>
<p><b>${v.goingCount}</b> going${v.spotsLeft != null ? ` | ${v.spotsLeft} spots left` : ''}${v.status === 'proposed' ? ` | ${v.voteCount}/${v.votesNeeded} votes` : ''}</p>
${v.impact ? `<p><b>Impact:</b> ${v.impact.checkedIn} people showed up. ${esc(v.impact.note)}</p>` : ''}`,
  });
}

function donationPage(d) {
  const v = donationView(d, null, null, true);
  return page({
    title: v.title, desc: `${v.kindLabel} | ${v.quantity} | ${v.status}`, image: v.media[0],
    body: `<span class="pill">${esc(v.status.replace('_', ' '))}</span><h1>${esc(v.title)}</h1><p>${esc(v.description)}</p>${imgs(v.media)}
<p><b>${esc(v.kindLabel)}</b> | ${esc(v.quantity)}${v.servings ? ` | serves ${v.servings}` : ''}</p>
<p>${esc(v.address || '')}</p><p class="muted">Best before ${esc(when(v.expiresAt))}. Only verified foundations can claim donations.</p>
${v.distribution ? `<p><b>Reached ${v.distribution.beneficiaries} people.</b> ${esc(v.distribution.note)}</p>` : ''}`,
  });
}

export function registerPublicRoutes(app) {
  const send = (reply, html) => reply.header('Cache-Control', 'public, max-age=60').type('text/html; charset=utf-8').send(html);
  const nf = () => new ApiError(404, 'NOT_FOUND', 'This page does not exist');
  app.get('/p/issues/:id', async (req, reply) => {
    const r = issueRow(Number(req.params.id) || 0); if (!r) throw nf();
    return send(reply, issuePage(r));
  });
  app.get('/p/gatherings/:id', async (req, reply) => {
    const r = gatheringRow(Number(req.params.id) || 0); if (!r) throw nf();
    return send(reply, gatheringPage(r));
  });
  app.get('/p/donations/:id', async (req, reply) => {
    const r = donationRow(Number(req.params.id) || 0); if (!r) throw nf();
    return send(reply, donationPage(r));
  });
}
