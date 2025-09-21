#!/usr/bin/env bash
set -euo pipefail

# Parameters with defaults
USERS=${USERS:-5}
POSTS_PER_USER=${POSTS_PER_USER:-10}
FOLLOW_NEXT=${FOLLOW_NEXT:-2}   # each user follows next K users (wrap-around)

HOST=${HOST:-cockroach1}
DATABASE=tinyinsta

echo "[init] Using USERS=$USERS POSTS_PER_USER=$POSTS_PER_USER FOLLOW_NEXT=$FOLLOW_NEXT"

# Wait for SQL to be ready
for i in {1..60}; do
  if cockroach sql --insecure --host="$HOST" -e "SELECT 1" >/dev/null 2>&1; then
    break
  fi
  echo "[init] Waiting for CockroachDB ($i/60)..."
  sleep 1
done

# Ensure database and schema are present
cockroach sql --insecure --host="$HOST" -e "CREATE DATABASE IF NOT EXISTS ${DATABASE};" >/dev/null
cockroach sql --insecure --host="$HOST" -f /init/schema.sql >/dev/null

# Generate seed SQL
cat >/tmp/init_gen.sql <<SQL
SET DATABASE = ${DATABASE};

-- Clean current data (FK-safe order)
DELETE FROM likes;
DELETE FROM follows;
DELETE FROM posts;
DELETE FROM users;

-- Users 1..USERS
INSERT INTO users (id, username, full_name)
SELECT i,
       'user_' || i::STRING,
       'User ' || i::STRING
FROM generate_series(1, ${USERS}) AS g(i)
ON CONFLICT (id) DO UPDATE SET username = excluded.username, full_name = excluded.full_name;

-- Posts: per author 1..USERS, seq 1..POSTS_PER_USER => id = author*1000 + seq
INSERT INTO posts (id, author_id, caption, created_at)
SELECT a*1000 + s AS id,
       a         AS author_id,
       'Post #' || (a*1000 + s)::STRING || ' by user ' || a::STRING,
       now() - ( (a*1000 + s) % 50 ) * INTERVAL '1 minute'
FROM generate_series(1, ${USERS}) AS ga(a)
JOIN generate_series(1, ${POSTS_PER_USER}) AS gs(s) ON true
ON CONFLICT (id) DO NOTHING;

-- Follows: each user follows next FOLLOW_NEXT users in a ring (skip self)
WITH params AS (
  SELECT ${USERS}::int u, ${FOLLOW_NEXT}::int k
)
INSERT INTO follows (follower_id, followee_id)
SELECT i AS follower_id,
       ((i + s - 1) % p.u) + 1 AS followee_id
FROM params p,
     generate_series(1, p.u) AS gi(i),
     generate_series(1, p.k) AS gs(s)
WHERE p.u >= 2 AND ((i + s - 1) % p.u) + 1 <> i
ON CONFLICT DO NOTHING;

-- Likes: user likes some posts from others
INSERT INTO likes (user_id, post_id, created_at)
SELECT u.id, p.id, now() - (p.id % 120) * INTERVAL '1 second'
FROM users u
JOIN posts p ON p.author_id <> u.id AND (p.id % (u.id+2)) = 0
ON CONFLICT DO NOTHING;
SQL

echo "[init] Seeding data..."
cockroach sql --insecure --host="$HOST" -f /tmp/init_gen.sql >/dev/null

# Build dynamic split statements
cat >/tmp/splits.sql <<SQL
SET DATABASE = ${DATABASE};
-- Split posts at 1000 boundaries between authors
SQL

if (( USERS >= 2 )); then
  for sp in $(seq 2 "$USERS"); do
    echo "ALTER TABLE posts SPLIT AT VALUES ($(( sp * 1000 )));" >> /tmp/splits.sql
  done
  echo "ALTER TABLE posts SCATTER;" >> /tmp/splits.sql

  echo "-- Split likes primary index by user_id" >> /tmp/splits.sql
  # Split likes@primary at (2..USERS)
  for sp in $(seq 2 "$USERS"); do
    echo "ALTER INDEX likes@primary SPLIT AT VALUES ($sp);" >> /tmp/splits.sql
  done
  echo "ALTER INDEX likes@primary SCATTER;" >> /tmp/splits.sql
fi

echo "[init] Applying splits/scatter..."
cockroach sql --insecure --host="$HOST" -f /tmp/splits.sql >/dev/null

echo "[init] Done."
