-- Pacing key that survives account deletion: the hash of the email, so
-- DELETE + register with the same address cannot reset the 40-a-day budget.
ALTER TABLE ad_rewards ADD COLUMN email_hash TEXT;
CREATE INDEX idx_ad_rewards_email ON ad_rewards(email_hash, created_at DESC);

-- Integrity check for a downloaded APK, supplied by the uploader: the Worker
-- cannot digest a 300 MB object inside its CPU budget.
ALTER TABLE product_files ADD COLUMN sha256 TEXT;
