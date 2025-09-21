#!/usr/bin/env bash
set -euo pipefail

# Parameters with defaults
USERS=${USERS:-5}
POSTS_PER_USER=${POSTS_PER_USER:-10}
FOLLOW_NEXT=${FOLLOW_NEXT:-2}

HOST=${HOST:-yb-tserver-1}
PORT=${PORT:-5433}
USER=${USER:-yugabyte}
DB=${DB:-tinyinsta}

echo "[yuga-init] Using USERS=$USERS POSTS_PER_USER=$POSTS_PER_USER FOLLOW_NEXT=$FOLLOW_NEXT"

# Wait for YSQL to be ready
for i in {1..60}; do
  if ysqlsh -h "$HOST" -p "$PORT" -U "$USER" -c "SELECT 1" >/dev/null 2>&1; then
    break
  fi
  echo "[yuga-init] Waiting for YSQL ($i/60)..."
  sleep 1
done

# Ensure DB exists (Postgres/YSQL doesn't support IF NOT EXISTS here)
ysqlsh -h "$HOST" -p "$PORT" -U "$USER" -c "CREATE DATABASE ${DB};" >/dev/null 2>&1 || true

# Apply schema (connect to DB)
ysqlsh -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -f /init/schema.sql >/dev/null

# Build seed SQL
cat >/tmp/yb_seed.sql <<SQL
-- Seed tinyinsta (YSQL)
\c ${DB}
-- Clean tables in FK-safe order
DELETE FROM follower_followee; 
DELETE FROM post; 
DELETE FROM users;

-- Users 1..USERS
INSERT INTO users(id, username, password)
SELECT i, 'user_'||i::text, 'pwd'
FROM generate_series(1, ${USERS}) AS g(i)
ON CONFLICT (id) DO UPDATE SET username = EXCLUDED.username, password = EXCLUDED.password;

-- Posts: id = author*1000 + seq
INSERT INTO post(id, user_id, image_path, description, created_at)
SELECT a*1000 + s,
       a,
       '/img/'|| (a*1000 + s)::text || '.jpg',
       'desc '|| (a*1000 + s)::text,
       NOW() - ((a*1000 + s) % 50) * interval '1 minute'
FROM generate_series(1, ${USERS}) AS ga(a)
JOIN generate_series(1, ${POSTS_PER_USER}) AS gs(s) ON true
ON CONFLICT (id) DO NOTHING;

-- Follows: ring follow of NEXT K users (skip self)
WITH params AS (
  SELECT ${USERS}::int u, ${FOLLOW_NEXT}::int k
)
INSERT INTO follower_followee(follower_id, followee_id)
SELECT i,
       ((i + s - 1) % p.u) + 1
FROM params p,
     generate_series(1, p.u) AS gi(i),
     generate_series(1, p.k) AS gs(s)
WHERE p.u >= 2 AND ((i + s - 1) % p.u) + 1 <> i
ON CONFLICT DO NOTHING;

VACUUM ANALYZE;
SQL

echo "[yuga-init] Seeding..."
ysqlsh -h "$HOST" -p "$PORT" -U "$USER" -f /tmp/yb_seed.sql >/dev/null
echo "[yuga-init] Done."
