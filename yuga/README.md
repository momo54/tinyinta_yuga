

Deployment of a YugabyteDB cluster (1 master, 5 tservers) with schema and data generation.

## Startup

From the `yuga/` directory:

```sh
docker compose up -d
```

Master UI: http://localhost:7001


## Connection

Run SQL from inside the container:
```sh
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte
```


## Run a SQL query

Run a query from inside the container:
```sh
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -c "SELECT * FROM my_table LIMIT 10;"
```

To execute a SQL script (example: `init/query_example.sql`):
```sh
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -f /init/query_example.sql
```


## Example: user timeline query

Suppose the user has ID 1.

- Without EXPLAIN (shows the timeline):
```sh
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -v userId=1 -f /init/query_example.sql
```




- With EXPLAIN (shows the execution plan):
```sh
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -c "EXPLAIN (ANALYZE, DIST) SELECT p.* FROM post p WHERE p.user_id = 1 OR p.user_id IN (SELECT followee_id FROM follower_followee WHERE follower_id = 1) ORDER BY p.created_at DESC LIMIT 50;"
```

## Find the shard of a post

To get the partition hash (shard) of a post:

```sql
SELECT id, yb_hash_code(id) AS shard_hash
FROM post
WHERE id = <POST_ID>;
```

Replace `<POST_ID>` with the desired post ID.

> To know which node (tserver) hosts this shard, open the Master UI (http://localhost:7001), go to the “Tables” section, click on the “post” table: you will see the hash range for each shard and the associated leader tserver.

## Scripts

- `init/schema.sql` — schema (tables, indexes)
- `init/init.sh` — parameterized seed for YSQL (defaults: USERS=5, POSTS_PER_USER=10, FOLLOW_NEXT=2)
- `init/query_example.sql` — timeline query
- `init/explain_query_example.sql` — plan
- `init/explain_dist_query_example.sql` — distributed plan

## Re-run init (seed)

Re-run the default seed (data only):
```sh
docker compose run --rm --no-deps yb-init
```

Override dataset size (examples):
```sh
# 12 users, 5 posts per user, each user follows next 3 users (ring)
docker compose run --rm --no-deps -e USERS=12 -e POSTS_PER_USER=5 -e FOLLOW_NEXT=3 yb-init
```

## Full reset (destroy data)

This will remove containers, network, and volumes, wiping all YB data:
```sh
docker compose down -v
docker compose up -d
```

## Shutdown

```sh
docker compose down -v
```
