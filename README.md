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
# tinyinsta (monorepo)

Comparatif de deux bases NewSQL sur un mini use-case "Instagram":

- Hash-based sharding: YugabyteDB (YSQL) dans `yuga/`
- Range-based sharding: TiDB (MySQL) dans `tidb/`

## Choisir une variante

- Yugabyte (hash): clés réparties via hash en tablettes (tablets). Très bon équilibrage automatique, fanout en lecture peut impliquer des scatter/gather si le schéma n’est pas pensé pour pruner.
- TiDB (range): splits par plages (regions) avec auto-scaling. Accès séquentiels peuvent être très efficaces; attention au hotspot si clé monotone.

## Lancer

- `cd yuga && docker compose up -d` — UI Master: http://localhost:7001 — SQL: port 5433 (PostgreSQL/ysql)
- `cd tidb && docker compose up -d` — SQL: port 4000 (MySQL)

Chaque variante a son README dédié avec les scripts d’init, de requêtes et d’EXPLAIN.

## Points de comparaison rapides

- API SQL: Yuga = PostgreSQL-compatible (YSQL), TiDB = MySQL-compatible
- Sharding: Yuga = hash → tablets; TiDB = range → regions
- Observabilité plan: Yuga → `EXPLAIN (ANALYZE, DIST)`; TiDB → `EXPLAIN ANALYZE`
- Pattern d’agrégation global: éviter fanout-on-read massif, favoriser fanout-on-write ou schémas qui prunent par clé (ex: partition par user)

## Liens

- Yugabyte: `./yuga/`
- TiDB: `./tidb/`

## Sharding demo (no-DB) 📊

Un petit outil Python sans dépendances pour visualiser range vs hash, les hotspots en séquentiel, l’auto-split et le salage des clés.

Chemin: `./sharding_demo/sharding_demo.py`

Exemples:

```bash
# Comparer range vs hash (splits uniformes auto)
python3 sharding_demo/sharding_demo.py --compare --shards 5 --n-keys 1000

# Range avec auto-split (réduit le hotspot de la queue)
python3 sharding_demo/sharding_demo.py --strategy range --n-keys 2000 --auto-split --progress-steps 6 --autosplit-threshold 0.35

# Range avec salage (répartit les écritures séquentielles)
python3 sharding_demo/sharding_demo.py --strategy range --n-keys 1000 --salt-buckets 16
```

Notes:
- Auto-split: coupe dynamiquement la dernière plage quand elle devient trop chaude.
- Salt-buckets: change la clé logique en (salt, key) pour disperser les inserts; trade-off: scans par plage font du fan-out sur les buckets.

