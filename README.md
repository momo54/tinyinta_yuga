## tinyinsta (monorepo)

Hands-on comparison of NewSQL / Distributed SQL systems on a small “Instagram-like” workload: sharding, range vs hash behavior, execution plans, and a pedagogical ASCII simulator.

### Repository layout

| Directory | Role | Core tech |
|-----------|------|-----------|
| `cockroach/` | 5-node CockroachDB cluster + deterministic seed + manual SPLIT/SCATTER (range sharding + leaseholder rebalancing) | CockroachDB v23 |
| `yuga/` | YugabyteDB cluster (hash tablets) + seed + EXPLAIN (ANALYZE, DIST) examples | YugabyteDB (YSQL) |
| `tidb/` | TiDB (PD + TiKV) cluster with auto-splitting regions + simple seed | TiDB |
| `sharding_demo/` | Python script to visualize range vs hash, auto-split and salted keys | Python 3 |

### Goals
1. Show sharding differences (hash vs range) and impact on hotspots & scans.
2. Demonstrate how to read execution plans across engines.
3. Compare pre-split, auto-split, scatter / rebalance strategies.
4. Provide a reproducible sandbox for timeline / follows / likes patterns.

---
## 1. Quick start (TL;DR)

Launch each cluster and run a simple count:

```bash
# CockroachDB
cd cockroach && docker compose up -d
docker compose exec cockroach1 cockroach sql --insecure --host=cockroach1 -e "SET DATABASE=tinyinsta; SELECT count(*) FROM posts;"

# YugabyteDB (hash)
cd yuga && docker compose up -d
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -d tinyinsta -c "SELECT count(*) FROM post;"

# TiDB (range)
cd tidb && docker compose up -d
docker exec -it tidb-tidb-1 mysql -h tidb-tidb-1 -P 4000 -u root -e "USE tinyinsta; SELECT COUNT(*) FROM post;"
```

Reset (example Cockroach): `docker compose down -v` then start again.

---
## 2. Sharding & partitioning

| Aspect | CockroachDB | YugabyteDB (YSQL) | TiDB |
|--------|--------------|-------------------|------|
| Primary style | Range (composite encoded key) | Hash (tablets) + size-based auto-split | Range (regions) auto-split |
| Manual pre-split | `ALTER TABLE ... SPLIT AT` + `SCATTER` | `CREATE TABLE ... SPLIT INTO N TABLETS` or flags | Region / split size config via PD |
| Auto-split trigger | Range growth + merge queues | Tablet size (`tablet_split_size_threshold_bytes`) | Region size thresholds |
| Rebalance focus | Leaseholder + replica balance | Tablet leader placement | Region leader scheduling |
| Hotspot mitigation | SPLIT AT + secondary key / client hashing | Key salting or composite hash | Custom partitioning / shuffle key |

### Inspecting distribution
- Cockroach: `SHOW RANGES FROM TABLE posts;`
- Yugabyte: `yb-admin list_tablets ysql.tinyinsta post 0`
- TiDB: PD UI Regions panel or `information_schema.tikv_region_status`

---
## 3. Timeline & likes queries

Cockroach (feed for user 1):
```sql
SELECT p.*
FROM tinyinsta.posts p
JOIN tinyinsta.follows f ON f.followee_id = p.author_id
WHERE f.follower_id = 1
ORDER BY p.created_at DESC
LIMIT 20;
```

Yugabyte (parameterized timeline):
```sh
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -d tinyinsta -v userId=1 -f /init/query_example.sql
```

TiDB (simple example):
```sql
SELECT p.* FROM post p WHERE p.user_id = 1 ORDER BY p.created_at DESC LIMIT 20;
```

Top liked posts (Cockroach):
```sql
SELECT post_id, COUNT(*) AS likes
FROM tinyinsta.likes
GROUP BY post_id
ORDER BY likes DESC
LIMIT 10;
```

---
## 4. Execution plans (EXPLAIN)

| Engine | Key commands |
|--------|--------------|
| Cockroach | `EXPLAIN`, `EXPLAIN ANALYZE`, `EXPLAIN (VEC)`, `EXPLAIN (DISTSQL)` |
| Yugabyte | `EXPLAIN (ANALYZE, DIST)` |
| TiDB | `EXPLAIN ANALYZE`, `EXPLAIN FORMAT='verbose'` |

Cockroach (distributed plan):
```bash
docker compose exec cockroach1 cockroach sql --insecure --host=cockroach1 -e \
  "SET DATABASE=tinyinsta; EXPLAIN (DISTSQL) SELECT p.* FROM posts p JOIN follows f ON f.followee_id = p.author_id WHERE f.follower_id = 1 ORDER BY p.created_at DESC LIMIT 20;"
```

Yugabyte (distributed plan):
```bash
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -d tinyinsta -c \
  "EXPLAIN (ANALYZE, DIST) SELECT p.* FROM post p WHERE p.user_id = 1 ORDER BY p.created_at DESC LIMIT 20;"
```

---
## 5. Seeding & data model

| Directory | Seed script | Key parameters |
|-----------|-------------|----------------|
| `cockroach/` | `init/init.sh` | `USERS`, `POSTS_PER_USER`, `FOLLOW_NEXT` + generated splits |
| `yuga/` | `init/init.sh` + `schema.sql` | `USERS`, `POSTS_PER_USER`, `FOLLOW_NEXT` (hash tablets) |
| `tidb/` | (to extend) | n/a |

Cockroach: post IDs = author*1000 + seq (aligns with split points 1000, 2000, ...). Yugabyte: BIGSERIAL IDs hashed into tablets.

---
## 6. Pedagogical sharding demo (`sharding_demo/`)

Python tool illustrating:
```bash
python3 sharding_demo/sharding_demo.py --compare --shards 5 --n-keys 500
python3 sharding_demo/sharding_demo.py --strategy range --n-keys 1500 --auto-split --progress-steps 5 --autosplit-threshold 0.3
python3 sharding_demo/sharding_demo.py --strategy range --n-keys 1000 --salt-buckets 8
```
Ideas: sequential hotspot, middle vs tail split, salting effect on range scans.

---
## 7. Roadmap / TODO

- Add “class-model” (OO) mode in `sharding_demo/`.
- Add data-movement estimator for rebalance / re-split scenarios.
- Create richer TiDB seed (posts + follows + likes) for parity.
- Optional lightweight Prometheus/Grafana dashboards.

---
## 8. Quick references

| Topic | Internal link |
|-------|---------------|
| Cockroach cluster | `cockroach/README.md` |
| Yugabyte cluster | `yuga/README.md` |
| TiDB cluster | `tidb/README.md` |
| Sharding demo | `sharding_demo/README.md` (if present) |

---
_Last synchronized: 2025‑09 (Cockroach, Yugabyte, TiDB directories)._ 

