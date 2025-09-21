-- Parameterized data generator for TiDB
USE tinyinsta;

-- Parameters (override by editing here if desired)
SET @n_users = 10000;
SET @posts_per_user = 10;
SET @follows_per_user = 50;

-- Helper: generate sequences via digit cartesian product (avoids recursion)
-- Build a small digits table [0..9]
DROP TABLE IF EXISTS digits;
CREATE TABLE digits (d TINYINT PRIMARY KEY);
INSERT INTO digits (d) VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);

-- Build seq up to @n_users using 5 digits (supports up to 100k) – adjust for larger
DROP TABLE IF EXISTS seq_users;
CREATE TABLE seq_users (n INT PRIMARY KEY);
INSERT INTO seq_users (n)
SELECT t.n FROM (
  SELECT d5.d*10000 + d4.d*1000 + d3.d*100 + d2.d*10 + d1.d + 1 AS n
  FROM digits d1
  JOIN digits d2
  JOIN digits d3
  JOIN digits d4
  JOIN digits d5
) t
WHERE t.n <= @n_users;

INSERT INTO users (id, username, created_at)
SELECT n AS id,
       CONCAT('user_', n) AS username,
       FROM_UNIXTIME(UNIX_TIMESTAMP() - FLOOR(RAND()*365*24*3600)) AS created_at
FROM seq_users;

-- Posts: build seq up to total posts similarly (supports up to 1e6 with 6 digits)
SET @total_posts = @n_users * @posts_per_user;
DROP TABLE IF EXISTS seq_posts;
CREATE TABLE seq_posts (n INT PRIMARY KEY);
INSERT INTO seq_posts (n)
SELECT t.n FROM (
  SELECT d6.d*100000 + d5.d*10000 + d4.d*1000 + d3.d*100 + d2.d*10 + d1.d + 1 AS n
  FROM digits d1
  JOIN digits d2
  JOIN digits d3
  JOIN digits d4
  JOIN digits d5
  JOIN digits d6
) t
WHERE t.n <= @total_posts;

INSERT INTO post (id, user_id, description, image_path, created_at)
SELECT n AS id,
       1 + FLOOR((n - 1) / @posts_per_user) AS user_id,
       CONCAT('Post #', n, ' from user ', 1 + FLOOR((n - 1) / @posts_per_user)) AS description,
       CONCAT('/images/', MOD(n, 1000), '.jpg') AS image_path,
       FROM_UNIXTIME(UNIX_TIMESTAMP() - FLOOR(RAND()*90*24*3600)) AS created_at
FROM seq_posts;

-- Follows: each user follows @follows_per_user pseudo-random others (avoid self)
DROP TABLE IF EXISTS seq_follow;
CREATE TABLE seq_follow (n INT PRIMARY KEY);
INSERT INTO seq_follow (n)
SELECT t.n FROM (
  SELECT d3.d*100 + d2.d*10 + d1.d + 1 AS n
  FROM digits d1
  JOIN digits d2
  JOIN digits d3
) t
WHERE t.n <= @follows_per_user;

-- Use CRC32-based pseudo-random mapping per (user, n) for deterministic yet "random-looking" followees
INSERT IGNORE INTO follower_followee (follower_id, followee_id, created_at)
SELECT u.id AS follower_id,
       CASE
         WHEN (1 + (CRC32(CONCAT(u.id, '-', f.n)) % @n_users)) = u.id
           THEN IF(u.id < @n_users, u.id + 1, 1)
         ELSE 1 + (CRC32(CONCAT(u.id, '-', f.n)) % @n_users)
       END AS followee_id,
       FROM_UNIXTIME(UNIX_TIMESTAMP() - FLOOR(RAND()*365*24*3600)) AS created_at
FROM users u
JOIN seq_follow f ON 1=1;

-- Analyze tables for better plans
ANALYZE TABLE users, post, follower_followee;

-- Cleanup helper tables
DROP TABLE IF EXISTS seq_follow;
DROP TABLE IF EXISTS seq_posts;
DROP TABLE IF EXISTS seq_users;
DROP TABLE IF EXISTS digits;

-- Example feed query (same shape as YSQL)
-- SET @userId = 1; -- you can override and run this manually via mysql client
-- SELECT p.*
-- FROM post p
-- WHERE p.user_id = @userId
--    OR p.user_id IN (
--         SELECT f.followee_id FROM follower_followee f WHERE f.follower_id = @userId
--       )
-- ORDER BY p.created_at DESC
-- LIMIT 50;
