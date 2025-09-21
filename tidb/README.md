

## Startup

From the `tidb/` directory, start everything with:

```sh
docker compose up -d
```

This will start 3 PD servers, 5 TiKV nodes, and 1 TiDB server, and automatically populate the database using the scripts in `init/` (schema and data).

Wait ~30-60s for everything to be ready.

# tinyinsta_tidb

Deployment of a local TiDB cluster (PD x3, TiKV x5, TiDB x1) with schema and data generation, for comparison with the YugabyteDB version.

## Connection

- MySQL protocol on port 4000 (on the host):
  - The TiDB container does not include the MySQL client. To run SQL queries, use the official MySQL client image as follows:

    ```sh
    docker run --rm -it --network=tidb_tidb-net mysql:8 mysql -h tidb -P 4000 -u root
    ```

  - To run a query directly (example: list databases):

    ```sh
    docker run --rm -it --network=tidb_tidb-net mysql:8 mysql -h tidb -P 4000 -u root -e "SHOW DATABASES;"
    ```

  - To list tables in the tinyinsta database:

    ```sh
    docker run --rm -it --network=tidb_tidb-net mysql:8 mysql -h tidb -P 4000 -u root -D tinyinsta -e "SHOW TABLES;"
    ```

- PD Dashboard (placement driver):
  - PD Dashboard (placement driver):
    - The dashboard of the current PD leader is always accessible from the host, but the port depends on which PD is leader:
      - pd0: http://localhost:2379/dashboard
      - pd1: http://localhost:2380/dashboard
      - pd2: http://localhost:2381/dashboard
    - If you are redirected to an URL like `http://pd2:2379/dashboard/`, use the port corresponding to the leader (e.g., `http://localhost:2381/dashboard` for pd2).
    - All three PDs expose their dashboard to the host on different ports.
  - Or check PD logs: `docker compose logs pd0`

## Schema and data

- The scripts are in `init/` and are automatically executed by the `init` container at startup:
  - `init/schema.sql` creates the `tinyinsta` database and tables (`users`, `post`, `follower_followee`).
  - `init/init.sql` populates the data (configurable at the top of the file).

- To re-run initialization:
  - `docker compose stop init && docker compose rm -f init && docker compose up -d init`

## Example: user timeline query

In a MySQL client connected to TiDB:

```sql
SET @userId = 1;
SELECT p.*
FROM post p
WHERE p.user_id = @userId
   OR p.user_id IN (
        SELECT f.followee_id FROM follower_followee f WHERE f.follower_id = @userId
      )
ORDER BY p.created_at DESC
LIMIT 50;
```

You can change `@userId` and observe the plan with `EXPLAIN ANALYZE`.

## Fault tolerance & node failure scenario

You can test TiDB’s fault tolerance by stopping one or more TiKV nodes while the cluster is running. For example:

```sh
docker stop tikv3
```

or stop multiple nodes:

```sh
docker stop tikv3 tikv4
```

The cluster will remain available as long as a majority of TiKV nodes are up (quorum). You can continue to run queries and observe how the system reacts to node failures.

To restart the nodes:

```sh
docker start tikv3 tikv4
```

You can monitor the cluster state and region distribution using the PD dashboard (http://localhost:2379/dashboard) or by checking the logs:

```sh
docker compose logs pd0
```


## Fault tolerance & node failure scenario

You can test TiDB’s fault tolerance by stopping one or more TiKV nodes while the cluster is running. For example:

```sh
docker stop tikv3
```

or stop multiple nodes:

```sh
docker stop tikv3 tikv4
```

The cluster will remain available as long as a majority of TiKV nodes are up (quorum). You can continue to run queries and observe how the system reacts to node failures.

To restart the nodes:

```sh
docker start tikv3 tikv4
```

You can monitor the cluster state and region distribution using the PD dashboard (http://localhost:2379/dashboard) or by checking the logs:

```sh
docker compose logs pd0
```
