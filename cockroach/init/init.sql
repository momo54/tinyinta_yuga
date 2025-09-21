-- Tiny Instagram demo seed for CockroachDB
-- Deterministic small dataset + manual splits to visualize ranges
USE tinyinsta;

-- Clean up previous runs (safe if tables are empty)
DROP TABLE IF EXISTS post;                -- legacy table (singular)
DROP TABLE IF EXISTS follower_followee;   -- legacy table name
-- Remove existing rows in FK-safe order
DELETE FROM likes;
DELETE FROM follows;
DELETE FROM posts;
DELETE FROM users;

-- Users (fixed IDs 1..5)
INSERT INTO users (id, username, full_name)
VALUES
  (1, 'alice', 'Alice A.'),
  (2, 'bob',   'Bob B.'),
  (3, 'carol', 'Carol C.'),
  (4, 'dave',  'Dave D.'),
  (5, 'eve',   'Eve E.')
ON CONFLICT (id) DO UPDATE SET username = excluded.username, full_name = excluded.full_name;

-- Each user posts 10 posts, with deterministic IDs 1001..5010
INSERT INTO posts (id, author_id, caption, created_at)
SELECT ids.p_id, g.author,
       'Post #' || ids.p_id::STRING || ' by user ' || g.author::STRING AS caption,
       now() - (ids.p_id % 50) * INTERVAL '1 minute'
FROM (
  SELECT author FROM (VALUES (1),(2),(3),(4),(5)) AS u(author)
) AS g
JOIN LATERAL (
  SELECT (g.author*1000 + seq) AS p_id
  FROM generate_series(1,10) AS seq
) AS ids ON true
ON CONFLICT (id) DO NOTHING;

-- Follow graph
INSERT INTO follows (follower_id, followee_id)
VALUES
  (1,2),(1,3),(2,1),(2,3),(3,1),(3,2),
  (4,1),(4,2),(5,1),(5,3)
ON CONFLICT DO NOTHING;

-- Likes: each user likes posts from others
INSERT INTO likes (user_id, post_id, created_at)
SELECT u.id, p.id, now() - (p.id % 120) * INTERVAL '1 second'
FROM users u
JOIN posts p ON p.author_id <> u.id AND (p.id % (u.id+2)) = 0
ON CONFLICT DO NOTHING;

-- Manual splits (sharding) on posts and likes to create multiple ranges
-- Posts use IDs 1001..5010 → split at 2000, 3000, 4000, 5000 then scatter
ALTER TABLE posts  SPLIT AT VALUES (2000);
ALTER TABLE posts  SPLIT AT VALUES (3000);
ALTER TABLE posts  SPLIT AT VALUES (4000);
ALTER TABLE posts  SPLIT AT VALUES (5000);
ALTER TABLE posts  SCATTER;

-- likes PK is (user_id, post_id) → splitting on user_id creates multiple ranges
ALTER INDEX likes@primary SPLIT AT VALUES (2), (3), (4), (5);
ALTER INDEX likes@primary SCATTER;
