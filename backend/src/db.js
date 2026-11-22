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
  created_at INTEGER NOT NULL,
  role TEXT NOT NULL DEFAULT 'citizen',
  org_name TEXT, reg_no TEXT,
  verified INTEGER NOT NULL DEFAULT 1,
  verify_status TEXT NOT NULL DEFAULT 'verified',
  verify_note TEXT,
  about TEXT, needs TEXT NOT NULL DEFAULT '[]', address TEXT,
  department_name TEXT, politician_id INTEGER, designation TEXT, city_id INTEGER,
  avatar_url TEXT, cover_url TEXT
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
  resolution_note TEXT,
  authority_status TEXT NOT NULL DEFAULT 'open',
  assigned_to TEXT,
  escalated INTEGER NOT NULL DEFAULT 0,
  escalated_by INTEGER, escalation_note TEXT,
  share_count INTEGER NOT NULL DEFAULT 0,
  media TEXT NOT NULL DEFAULT '[]'
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
  created_at INTEGER NOT NULL,
  media TEXT NOT NULL DEFAULT '[]',
  actor_role TEXT,
  kind TEXT NOT NULL DEFAULT 'status'
);
CREATE TABLE IF NOT EXISTS notifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  issue_id INTEGER,
  read INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  ref_type TEXT, ref_id INTEGER
);
CREATE TABLE IF NOT EXISTS user_badges (
  user_id INTEGER NOT NULL REFERENCES users(id),
  badge_key TEXT NOT NULL,
  earned_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, badge_key)
);
CREATE TABLE IF NOT EXISTS likes (
  target_type TEXT NOT NULL,
  target_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,
  PRIMARY KEY (target_type, target_id, user_id)
);
CREATE TABLE IF NOT EXISTS comments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  target_type TEXT NOT NULL CHECK (target_type IN ('issue','gathering','donation')),
  target_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL REFERENCES users(id),
  body TEXT NOT NULL,
  media TEXT NOT NULL DEFAULT '[]',
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_comments_target ON comments(target_type, target_id);
CREATE TABLE IF NOT EXISTS clubs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT 'other',
  hue INTEGER NOT NULL DEFAULT 150,
  owner_id INTEGER NOT NULL REFERENCES users(id),
  avatar_url TEXT, cover_url TEXT,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS club_members (
  club_id INTEGER NOT NULL REFERENCES clubs(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  joined_at INTEGER NOT NULL,
  PRIMARY KEY (club_id, user_id)
);
CREATE TABLE IF NOT EXISTS gatherings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL,
  lat REAL NOT NULL, lng REAL NOT NULL,
  address TEXT,
  start_at INTEGER NOT NULL,
  end_at INTEGER,
  status TEXT NOT NULL DEFAULT 'upcoming',
  organizer_id INTEGER NOT NULL REFERENCES users(id),
  club_id INTEGER REFERENCES clubs(id),
  capacity INTEGER,
  media TEXT NOT NULL DEFAULT '[]',
  impact_note TEXT,
  completed_at INTEGER,
  reminded INTEGER NOT NULL DEFAULT 0,
  share_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_gatherings_start ON gatherings(start_at);
CREATE TABLE IF NOT EXISTS gathering_rsvps (
  gathering_id INTEGER NOT NULL REFERENCES gatherings(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,
  checked_in_at INTEGER,
  PRIMARY KEY (gathering_id, user_id)
);
CREATE TABLE IF NOT EXISTS gathering_rsvp_awards (
  gathering_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  PRIMARY KEY (gathering_id, user_id)
);
CREATE TABLE IF NOT EXISTS gathering_votes (
  gathering_id INTEGER NOT NULL REFERENCES gatherings(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,
  PRIMARY KEY (gathering_id, user_id)
);
CREATE TABLE IF NOT EXISTS donations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  quantity TEXT NOT NULL DEFAULT '',
  servings INTEGER,
  veg TEXT NOT NULL DEFAULT 'na',
  prepared_at INTEGER,
  expires_at INTEGER NOT NULL,
  lat REAL NOT NULL, lng REAL NOT NULL,
  address TEXT, pickup_note TEXT,
  media TEXT NOT NULL DEFAULT '[]',
  hygiene_ack INTEGER NOT NULL DEFAULT 0,
  donor_id INTEGER NOT NULL REFERENCES users(id),
  status TEXT NOT NULL DEFAULT 'available',
  claimed_by INTEGER REFERENCES users(id),
  claimed_at INTEGER, eta_at INTEGER, lock_expires_at INTEGER,
  picked_up_at INTEGER, distributed_at INTEGER,
  dist_note TEXT, dist_beneficiaries INTEGER, dist_media TEXT,
  share_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_donations_status ON donations(status);
CREATE TABLE IF NOT EXISTS donation_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  donation_id INTEGER NOT NULL REFERENCES donations(id),
  status TEXT NOT NULL,
  note TEXT,
  user_id INTEGER,
  created_at INTEGER NOT NULL
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
