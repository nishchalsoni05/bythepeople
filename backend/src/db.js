import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const dataDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'data');
fs.mkdirSync(dataDir, { recursive: true });
export const DB_PATH = process.env.DB_PATH || path.join(dataDir, 'bythepeople.db');

export const db = new DatabaseSync(DB_PATH);
db.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;');

export const SCHEMA = `
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  salt TEXT NOT NULL,
  points INTEGER NOT NULL DEFAULT 0,
  volunteer INTEGER NOT NULL DEFAULT 0,
  alert_radius_km REAL NOT NULL DEFAULT 5,
  home_lat REAL, home_lng REAL,
  last_lat REAL, last_lng REAL, last_ts INTEGER,
  hue INTEGER NOT NULL DEFAULT 200,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  token TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS areas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('region','state','city','ward')),
  parent_id INTEGER REFERENCES areas(id),
  lat REAL, lng REAL, radius_km REAL
);
CREATE INDEX IF NOT EXISTS idx_areas_kind ON areas(kind);
CREATE TABLE IF NOT EXISTS politicians (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  party TEXT NOT NULL,
  constituency TEXT NOT NULL,
  level TEXT NOT NULL,
  parent_id INTEGER REFERENCES politicians(id),
  area_id INTEGER REFERENCES areas(id),
  city_id INTEGER, state_id INTEGER, region_id INTEGER,
  hue INTEGER NOT NULL DEFAULT 20,
  tagline TEXT
);
CREATE TABLE IF NOT EXISTS issues (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL,
  lat REAL NOT NULL, lng REAL NOT NULL,
  address TEXT,
  reporter_id INTEGER NOT NULL REFERENCES users(id),
  politician_id INTEGER REFERENCES politicians(id),
  ward_id INTEGER, city_id INTEGER, state_id INTEGER, region_id INTEGER,
  status TEXT NOT NULL DEFAULT 'open',
  round INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  event_at INTEGER,
  scheduled_at INTEGER,
  resolved_at INTEGER,
  closed_at INTEGER,
  resolution_note TEXT
);
CREATE INDEX IF NOT EXISTS idx_issues_status ON issues(status);
CREATE INDEX IF NOT EXISTS idx_issues_pol ON issues(politician_id);
CREATE INDEX IF NOT EXISTS idx_issues_city ON issues(city_id);
CREATE INDEX IF NOT EXISTS idx_issues_state ON issues(state_id);
CREATE TABLE IF NOT EXISTS supports (
  issue_id INTEGER NOT NULL REFERENCES issues(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,
  PRIMARY KEY (issue_id, user_id)
);
CREATE TABLE IF NOT EXISTS linked_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  issue_id INTEGER NOT NULL REFERENCES issues(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  note TEXT,
  created_at INTEGER NOT NULL,
  UNIQUE (issue_id, user_id)
);
CREATE TABLE IF NOT EXISTS volunteers (
  issue_id INTEGER NOT NULL REFERENCES issues(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  role TEXT NOT NULL DEFAULT 'volunteer',
  joined_at INTEGER NOT NULL,
  PRIMARY KEY (issue_id, user_id)
);
CREATE TABLE IF NOT EXISTS verifications (
  issue_id INTEGER NOT NULL REFERENCES issues(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  round INTEGER NOT NULL,
  approve INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (issue_id, user_id, round)
);
CREATE TABLE IF NOT EXISTS status_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  issue_id INTEGER NOT NULL REFERENCES issues(id),
  status TEXT NOT NULL,
  note TEXT,
  user_id INTEGER,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS notifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  issue_id INTEGER,
  read INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS user_badges (
  user_id INTEGER NOT NULL REFERENCES users(id),
  badge_key TEXT NOT NULL,
  earned_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, badge_key)
);
`;

export function initSchema() {
  db.exec(SCHEMA);
}

/** Drops everything (used by the seed so the schema always matches the code). */
export function resetSchema() {
  db.exec('PRAGMA foreign_keys = OFF');
  const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").all();
  for (const t of tables) db.exec(`DROP TABLE IF EXISTS ${t.name}`);
  db.exec('PRAGMA foreign_keys = ON');
  db.exec(SCHEMA);
}

export function tx(fn) {
  db.exec('BEGIN');
  try {
    const r = fn();
    db.exec('COMMIT');
    return r;
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}
