
-- Data generation for tinyinsta_yuga
-- Make sure to run schema.sql first!
\set n_users 10000
\set posts_per_user 10
\set follows_per_user 50

-- Users
INSERT INTO users(username, password)
SELECT 'user_'||g, 'pwd'
FROM generate_series(1, :n_users) AS g;

-- Follows
WITH params AS (
  SELECT :n_users::int n, :follows_per_user::int k
)
INSERT INTO follower_followee(follower_id, followee_id)
SELECT f AS follower_id,
       ((random()* (p.n-1))::int + 1) AS followee_id
FROM params p,
     LATERAL generate_series(1, p.n) u(f),
     LATERAL generate_series(1, p.k) r
WHERE ((random()* (p.n-1))::int + 1) <> f
ON CONFLICT DO NOTHING;

-- Posts
INSERT INTO post(user_id, image_path, description, created_at)
SELECT ((random()*(:n_users-1))::int + 1) AS user_id,
       '/img/'||g||'.jpg',
       'desc '||g,
       NOW() - (random()* interval '30 days')
FROM generate_series(1, :n_users * :posts_per_user) g;

VACUUM ANALYZE;
