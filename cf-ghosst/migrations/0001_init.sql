PRAGMA foreign_keys = ON;

CREATE TABLE users (
  id            TEXT PRIMARY KEY,
  email         TEXT NOT NULL UNIQUE COLLATE NOCASE,
  password_hash TEXT NOT NULL,
  display_name  TEXT NOT NULL DEFAULT '',
  coins         INTEGER NOT NULL DEFAULT 0 CHECK (coins >= 0),
  is_admin      INTEGER NOT NULL DEFAULT 0,
  created_at    TEXT NOT NULL,
  deleted_at    TEXT
);

CREATE TABLE sessions (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  refresh_hash TEXT NOT NULL UNIQUE,
  family       TEXT NOT NULL,
  user_agent   TEXT NOT NULL DEFAULT '',
  created_at   TEXT NOT NULL,
  expires_at   TEXT NOT NULL,
  revoked_at   TEXT
);
CREATE INDEX idx_sessions_user ON sessions(user_id);

CREATE TABLE products (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  cost        INTEGER NOT NULL DEFAULT 50 CHECK (cost >= 0),
  active      INTEGER NOT NULL DEFAULT 1,
  description TEXT NOT NULL DEFAULT '',
  youtube_url TEXT NOT NULL DEFAULT '',
  type        TEXT NOT NULL DEFAULT 'key' CHECK (type IN ('key', 'apk', 'file')),
  version     TEXT NOT NULL DEFAULT '',
  file_size   TEXT NOT NULL DEFAULT '',
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);
CREATE INDEX idx_products_active ON products(active, name);

CREATE TABLE product_images (
  id         TEXT PRIMARY KEY,
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  object_key TEXT NOT NULL,
  position   INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_product_images ON product_images(product_id, position);

CREATE TABLE product_durations (
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  label      TEXT NOT NULL,
  cost       INTEGER NOT NULL CHECK (cost >= 0),
  PRIMARY KEY (product_id, label)
);

CREATE TABLE product_files (
  product_id   TEXT PRIMARY KEY REFERENCES products(id) ON DELETE CASCADE,
  object_key   TEXT NOT NULL,
  filename     TEXT NOT NULL,
  size         INTEGER NOT NULL DEFAULT 0,
  content_type TEXT NOT NULL DEFAULT '',
  updated_at   TEXT NOT NULL
);

CREATE TABLE keys (
  id         TEXT PRIMARY KEY,
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  key_value  TEXT NOT NULL,
  status     TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'claimed')),
  duration   TEXT NOT NULL DEFAULT '',
  claimed_by TEXT,
  claimed_at TEXT,
  created_at TEXT NOT NULL,
  UNIQUE (product_id, key_value)
);
-- Covers the claim pick: product + status + duration pool, oldest first.
CREATE INDEX idx_keys_pick ON keys(product_id, status, duration, created_at);

CREATE TABLE claims (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id   TEXT NOT NULL,
  product_name TEXT NOT NULL DEFAULT '',
  key_id       TEXT NOT NULL,
  key_text     TEXT NOT NULL,
  cost         INTEGER NOT NULL DEFAULT 0,
  duration     TEXT NOT NULL DEFAULT '',
  object_key   TEXT,
  created_at   TEXT NOT NULL
);
CREATE INDEX idx_claims_user ON claims(user_id, created_at DESC);
-- One purchase per app-store item (matches today's "already owned" rule).
CREATE UNIQUE INDEX ux_claims_user_product ON claims(user_id, product_id)
  WHERE object_key IS NOT NULL;

CREATE TABLE ad_rewards (
  id         TEXT PRIMARY KEY, -- AdMob transaction_id -> replay protection
  user_id    TEXT NOT NULL,
  reward     INTEGER NOT NULL,
  ad_unit    TEXT NOT NULL DEFAULT '',
  event_time TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);
CREATE INDEX idx_ad_rewards_user ON ad_rewards(user_id, created_at DESC);

CREATE TABLE idempotency (
  key        TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL,
  response   TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_idempotency_created ON idempotency(created_at);
