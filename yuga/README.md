

Deployment of a YugabyteDB cluster (1 master, 5 tservers) with schema and data generation.

## Startup

From the `yuga/` directory:

```sh
docker compose up -d
```

Master UI: http://localhost:7001


## Connection

Run SQL from inside the container (connect to the tinyinsta DB):
```sh
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -d tinyinsta
```
Tip (interactive): inside ysqlsh you can switch DBs with `\c tinyinsta` and list DBs with `\l`.


## Run a SQL query

Run a query from inside the container:
```sh
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -d tinyinsta -c "SELECT * FROM users LIMIT 10;"
```

To execute a SQL script (example: `init/query_example.sql`):
```sh
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -d tinyinsta -f /init/query_example.sql
```


## Example: user timeline query

Suppose the user has ID 1.

- Without EXPLAIN (shows the timeline):
```sh
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -d tinyinsta -v userId=1 -f /init/query_example.sql
```




- With EXPLAIN (shows the execution plan):
```sh
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -d tinyinsta -c "EXPLAIN (ANALYZE, DIST) SELECT p.* FROM post p WHERE p.user_id = 1 OR p.user_id IN (SELECT followee_id FROM follower_followee WHERE follower_id = 1) ORDER BY p.created_at DESC LIMIT 50;"
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

CLI alternative (map the hash to a tablet and its leader):

1) Get the hash in hex (easier to match ranges shown by YB):
```sh
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -d tinyinsta -c \
	"SELECT id, yb_hash_code(id) AS shard_hash_dec, lpad(to_hex(yb_hash_code(id)), 4, '0') AS shard_hash_hex FROM post WHERE id = <POST_ID>;"
```

2) Get the `table_id` of `public.post` (avoid `-it` when capturing output):
```sh
TABLE_ID=$(docker exec yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -d tinyinsta -Atc "SELECT table_id FROM yb_table_properties('public.post'::regclass);")
echo "table_id=$TABLE_ID"
```

3) List tablets and their leaders (look for the hash range containing your `shard_hash_hex` from step 1):
```sh
docker exec -it yb-master yb-admin --master_addresses=yb-master:7100 list_tablets "tableid.$TABLE_ID" 0
```

Alternative without `table_id` (pass namespace TYPE and name as two args):
```sh
docker exec -it yb-master yb-admin --master_addresses=yb-master:7100 list_tablets ysql.tinyinsta post 0
```

If unsure about namespaces, list them first:
```sh
docker exec -it yb-master yb-admin --master_addresses=yb-master:7100 list_namespaces ysql
docker exec -it yb-master yb-admin --master_addresses=yb-master:7100 list_tables ysql.tinyinsta
```

In the output, identify the tablet whose partition hash range (e.g. `[0000, 4000)`) contains your hex hash; the reported `LEADER` tserver for that tablet is the node serving your row.

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
