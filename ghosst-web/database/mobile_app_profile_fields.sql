-- One-shot: profile bio + cover photo on the shared users row.
-- Safe to re-run; each column is added only when missing.

SET @bio_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'bio'
);
SET @sql = IF(@bio_exists = 0,
  'ALTER TABLE users ADD COLUMN bio VARCHAR(300) NOT NULL DEFAULT ''''',
  'SELECT 1');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @cover_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'cover_url'
);
SET @sql = IF(@cover_exists = 0,
  'ALTER TABLE users ADD COLUMN cover_url VARCHAR(1000) NULL',
  'SELECT 1');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
