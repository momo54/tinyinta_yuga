## Running a Query from a File

You can execute a SQL query from a file in one command. For example, to run the provided example query:

```sh
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte -f /init/query_example.sql
```

You can edit `init/query_example.sql` to change the query or the user id.
# tinyinsta_yuga


This project deploys a 3-node YugabyteDB cluster with a simple Instagram-like database schema and populates it with sample data.

**Schema and data generation are now split into two files:**
- `init/schema.sql` — contains only the schema (tables, indexes)
- `init/init.sql` — contains only the data generation (users, follows, posts)

Both scripts are run automatically in order by the `yb-client` service at startup.

## Prerequisites
- Docker and Docker Compose installed

## Starting the Cluster

1. Clone this repository or copy the files to your machine.
2. Navigate to the project folder:
   ```sh
   cd tinyinsta_yuga
   ```
3. Start the cluster and initialize the database (recommended in detached mode to keep your terminal available):
   ```sh
   docker compose up -d
   ```
   This will start 1 master, 3 tservers, and a client to initialize the schema and data.

   If you want to see the logs live, you can use:
   ```sh
   docker compose logs -f
   ```

## Accessing YugabyteDB Web UI

- **YugabyteDB Master UI:** [http://localhost:7001](http://localhost:7001)

You can use this UI to monitor the cluster status and inspect tables.

## Connecting to the Database


Once the containers are running, connect to the database from inside the tserver container with:
```sh
docker exec -it yb-tserver-1 ysqlsh -h yb-tserver-1 -U yugabyte
```

Or from your host (if you have `ysqlsh` installed):
```sh
ysqlsh -h localhost -p 5433 -U yugabyte
```

> **Note:** The simple command `docker exec -it yb-tserver-1 ysqlsh -U yugabyte` may fail with "connection refused". Always specify `-h yb-tserver-1` as the host when connecting from inside the container.

## Database Structure

- `users`: users
- `post`: posts
- `follower_followee`: follow relationships

The schema is in `init/schema.sql` and the data generation in `init/init.sql`.

## Example Query

To fetch the 50 most recent posts from a user and those they follow:

```sql
-- Replace :userId with the desired user id
SELECT p.*
FROM post p
WHERE p.user_id = :userId
   OR p.user_id IN (
        SELECT followee_id
        FROM follower_followee
        WHERE follower_id = :userId
     )
ORDER BY p.created_at DESC
LIMIT 50;
```

## Stopping and Removing the Cluster

```sh
docker compose down -v
```


## Customization

- Edit `init/schema.sql` to change the schema (tables, indexes, etc).
- Edit `init/init.sql` to change the data generation (number of users, posts, etc).

---

For questions, open an issue or contact the maintainer.
