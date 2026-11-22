import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { ApiError } from './util.js';
import { authUser } from './auth.js';
import { CONFIG } from './config.js';

export const UPLOAD_DIR = process.env.UPLOAD_DIR
  || path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'uploads');
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

const MIME_EXT = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp',
  'video/mp4': 'mp4', 'video/quicktime': 'mov',
};
const EXT_MIME = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp', mp4: 'video/mp4', mov: 'video/quicktime' };

export function saveMedia(buf, ext) {
  const name = `${crypto.randomBytes(8).toString('hex')}.${ext}`;
  fs.writeFileSync(path.join(UPLOAD_DIR, name), buf);
  return `/uploads/${name}`;
}

export function registerMediaRoutes(app) {
  app.post('/media', async (req) => {
    authUser(req);
    const b = req.body || {};
    const ext = MIME_EXT[b.mime];
    if (!ext) throw new ApiError(400, 'BAD_MIME', 'Unsupported file type. Use JPEG, PNG, WebP, MP4 or MOV.');
    let data = String(b.dataBase64 || '');
    const comma = data.indexOf(',');
    if (data.startsWith('data:') && comma > 0) data = data.slice(comma + 1);
    if (!data) throw new ApiError(400, 'BAD_MEDIA', 'No file data received');
    const buf = Buffer.from(data, 'base64');
    if (!buf.length) throw new ApiError(400, 'BAD_MEDIA', 'The file is empty or not valid base64');
    if (buf.length > CONFIG.maxMediaMb * 1024 * 1024) {
      throw new ApiError(413, 'TOO_LARGE', `That file is too large. The limit is ${CONFIG.maxMediaMb} MB.`);
    }
    return { url: saveMedia(buf, ext) };
  });

  app.get('/uploads/:name', async (req, reply) => {
    const name = String(req.params.name);
    if (!/^[A-Za-z0-9._-]+$/.test(name) || name.includes('..')) throw new ApiError(404, 'NOT_FOUND', 'File not found');
    const file = path.join(UPLOAD_DIR, name);
    if (!fs.existsSync(file)) throw new ApiError(404, 'NOT_FOUND', 'File not found');
    const mime = EXT_MIME[name.split('.').pop().toLowerCase()] || 'application/octet-stream';
    reply.header('Cache-Control', 'public, max-age=86400').type(mime);
    return fs.readFileSync(file);
  });
}
