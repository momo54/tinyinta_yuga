# tinyinsta_cockroach

Tiny Instagram-style demo on CockroachDB v23, 5-node cluster with deterministic seed and manual range splits.

## Startup

From the `cockroach/` directory:

```sh
docker compose up -d
```

This starts a 5-node CockroachDB cluster and runs `init/` scripts:
- `schema.sql`: creates `users`, `posts`, `follows`, `likes` + helpful indexes
- `init.sh`: parameterized seed (defaults: 5 users, 10 posts/user) and SPLIT/SCATTER on `posts` and `likes`

Wait ~10–20s for everything to be ready.

## Connection

- SQL (PostgreSQL protocol) on node 1:
  - Inside Docker:
    ```sh
    docker compose exec cockroach1 cockroach sql --insecure --host=cockroach1:26257
    ```
  - From host (if you have psql):
    ```sh
    psql "postgresql://root@localhost:26257/tinyinsta?sslmode=disable"
    ```
- Web UI:
  - Node 1: http://localhost:8080
  - Node 2: http://localhost:8081
  - Node 3: http://localhost:8082
  - Node 4: http://localhost:8083
  - Node 5: http://localhost:8084

## Example queries

Basic counts and range layout:
```sh
docker compose exec cockroach1 ./cockroach sql --insecure --host=cockroach1 -e \
  "SET DATABASE=tinyinsta; \
   SELECT 'users' tbl, count(*) FROM users UNION ALL \
          SELECT 'posts', count(*) FROM posts UNION ALL \
          SELECT 'follows', count(*) FROM follows UNION ALL \
          SELECT 'likes', count(*) FROM likes; \
   SHOW RANGES FROM TABLE posts;"
```

Feed for user 1 (people they follow, newest first):
```sql
SELECT p.*
FROM tinyinsta.posts p
JOIN tinyinsta.follows f ON f.followee_id = p.author_id
WHERE f.follower_id = 1
ORDER BY p.created_at DESC
LIMIT 20;
```

Likes per post:
```sql
SELECT post_id, COUNT(*) AS likes
FROM tinyinsta.likes
GROUP BY post_id
ORDER BY likes DESC
LIMIT 10;
```

## Explain plans (CockroachDB)

Run logical, physical and runtime execution plans for the feed query:

```sh
# EXPLAIN (logical plan with estimates)
docker compose exec cockroach1 cockroach sql --insecure --host=cockroach1 -e \
  "SET DATABASE=tinyinsta; EXPLAIN SELECT p.* FROM posts p JOIN follows f ON f.followee_id = p.author_id WHERE f.follower_id = 1 ORDER BY p.created_at DESC LIMIT 20;"

# EXPLAIN ANALYZE (executes the query and shows per-operator stats)
docker compose exec cockroach1 cockroach sql --insecure --host=cockroach1 -e \
  "SET DATABASE=tinyinsta; EXPLAIN ANALYZE SELECT p.* FROM posts p JOIN follows f ON f.followee_id = p.author_id WHERE f.follower_id = 1 ORDER BY p.created_at DESC LIMIT 20;"

# EXPLAIN (VEC) shows the vectorized physical operators (batch engine)
docker compose exec cockroach1 cockroach sql --insecure --host=cockroach1 -e \
  "SET DATABASE=tinyinsta; EXPLAIN (VEC) SELECT p.* FROM posts p JOIN follows f ON f.followee_id = p.author_id WHERE f.follower_id = 1 ORDER BY p.created_at DESC LIMIT 20;"

# EXPLAIN (DISTSQL) highlights the distributed flow across nodes
docker compose exec cockroach1 cockroach sql --insecure --host=cockroach1 -e \
  "SET DATABASE=tinyinsta; EXPLAIN (DISTSQL) SELECT p.* FROM posts p JOIN follows f ON f.followee_id = p.author_id WHERE f.follower_id = 1 ORDER BY p.created_at DESC LIMIT 20;"
```

Tips:
- Use the Web UI (Statements / Transactions) to view historical statements, plans, and execution stats.
- Correlate with range layout: `SHOW RANGES FROM TABLE posts;` and `SHOW RANGES FROM INDEX likes@primary;`.

Inspect ranges (examples):
```sql
-- SHOW RANGES FROM TABLE posts;
-- SHOW RANGE FROM TABLE posts FOR ROW (2100);
```

## Re-run init

Re-run the full seed (data + splits/scatter) with defaults:
```sh
docker compose run --rm --no-deps init-cockroach
```

Override dataset size (examples):
```sh
# 12 users, 5 posts per user, each user follows next 3 users (ring)
docker compose run --rm --no-deps -e USERS=12 -e POSTS_PER_USER=5 -e FOLLOW_NEXT=3 init-cockroach

# 50 users, 20 posts per user
docker compose run --rm --no-deps -e USERS=50 -e POSTS_PER_USER=20 init-cockroach
```

Only re-apply splits/scatter (keep existing data):
```sh
docker compose run --rm --no-deps --entrypoint '' \
  init-cockroach /bin/bash -lc "cockroach sql --insecure --host=cockroach1 -f /init/splits.sql"
```

## Full reset (destroy data)

This will remove containers, network, and persistent volumes, wiping all CockroachDB data:

```sh
docker compose down -v
docker compose up -d
```

The cluster will boot clean. The `init-cockroach` service should run automatically, but if you need to re-run it manually:

```sh
docker compose run --rm --no-deps init-cockroach
```

## Fault tolerance

Stop any node to see survivability (quorum maintained):
```sh
docker stop cockroach2
```

Bring it back:
```sh
docker start cockroach2
```

Monitor in the Web UI (see ports above).
