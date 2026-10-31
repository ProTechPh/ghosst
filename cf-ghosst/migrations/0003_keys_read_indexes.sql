-- Free-plan D1 counts every index entry it scans as a row read, and both of the
-- hot paths here sorted the whole stock pool per call: the claim pick ordered
-- product+status by created_at through idx_keys_pick (duration sits between,
-- so SQLite built a temp B-tree) and the admin list ordered the table.
CREATE INDEX IF NOT EXISTS idx_keys_pick_time ON keys(product_id, status, created_at);
CREATE INDEX IF NOT EXISTS idx_keys_created ON keys(created_at);
