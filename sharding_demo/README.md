# Sharding demo (range vs hash)

A tiny Python program to visualize how keys are assigned to shards using:
- Range sharding (by key ranges)
- Hash sharding (SHA1(key) % N)

No database required. Outputs ASCII histograms for distribution and a simple sequential ingest progression to show potential hotspots.

## Quick start

Run with Python 3.9+ (no dependencies):

```bash
python3 sharding_demo/sharding_demo.py --compare --shards 5 --n-keys 1000
```

Example: only range sharding with explicit splits (4 splits → 5 shards):

```bash
python3 sharding_demo/sharding_demo.py --strategy range --shards 5 --n-keys 1000 --splits 200,400,700,900
```

Example: hash sharding:

```bash
python3 sharding_demo/sharding_demo.py --strategy hash --shards 4 --n-keys 500
```

Salted keys with range sharding (spreads sequential inserts across buckets):

```bash
python3 sharding_demo/sharding_demo.py --strategy range --shards 4 --n-keys 1000 --salt-buckets 16
```
Progression and per-bucket view:
```bash
python3 sharding_demo/sharding_demo.py --strategy range --n-keys 500 --salt-buckets 8 --progress-steps 5
```

Auto-splitting (range only):

```bash
python3 sharding_demo/sharding_demo.py --strategy range --shards 4 --n-keys 2000 --auto-split --progress-steps 6
# Split au milieu (plus réaliste):
python3 sharding_demo/sharding_demo.py --strategy range --shards 1 --n-keys 2000 --auto-split --autosplit-where middle

# Visualiser la charge par nœud et le rebalance
python3 sharding_demo/sharding_demo.py --strategy range --n-keys 1000 --auto-split --nodes 3 --rebalance-after-split --autosplit-where middle
```
or compare both with auto-split enabled for range:
```bash
python3 sharding_demo/sharding_demo.py --compare --shards 5 --n-keys 1000 --auto-split
```

## Options

- `--strategy`: `range` or `hash` (default: `hash`)
- `--shards`: number of shards (default: 4)
- `--n-keys`: number of integer keys (1..N) to simulate (default: 1000)
- `--splits`: comma-separated split points for range sharding; if omitted, even splits are generated automatically
- `--compare`: run both strategies side by side
- `--progress-steps`: how many checkpoints to show for sequential ingest (default: 5)
- `--auto-split`: when using `range`, dynamically split the last range if it becomes a hotspot during sequential ingest progression
- `--autosplit-threshold`: fraction (0<val<1) of inserted keys currently in the last range that triggers a split (default: 0.4)
- `--salt-buckets`: when >0 with `--strategy range`, simulate salted keys (bucket = hash(key) % buckets). Shows per-range and per-bucket distributions.
- `--autosplit-where`: `current` (split à la clé courante) ou `middle` (split au milieu de la dernière plage)
- `--nodes`: avec `range+auto-split`, affiche une distribution par nœud (répartition des ranges)
- `--rebalance-after-split`: avec `--nodes`, assigne la nouvelle sous-plage droite au nœud le moins chargé (visualise un rebalance simplifié)

## What it shows

- Distribution for sequential keys (1..N): hash spreads evenly; range concentrates early inserts in the first range(s)
- Distribution for random keys: both can be balanced if splits are well chosen; hash tends to be naturally balanced
- Sequential ingest progression: watch hotspots appear under range sharding when ingest is ordered by key
	- With `--auto-split`, see how dynamic splits reduce the hotspot by creating new ranges
	- With `--salt-buckets`, see how salting spreads writes while keeping range sharding (trade-off: range scans fan out across buckets)

## Why this matters

- Range sharding is great for range scans and locality but can suffer hotspots during monotonic inserts unless you split or randomize keys
- Hash sharding balances writes, but range scans across many shards can be expensive
- Salting keys (e.g., 8–64 buckets) usually eliminates the sequential hotspot for range sharding, at the cost of fan-out for range scans

Tweak `--shards`, `--n-keys`, and `--splits` to explore behaviors.

## Example output (mini capture)

Range vs Hash (compare mode):

```text
============ RANGE ============

Sequential keys (overall)
	shard 00:    100 ( 20.0%) |########################################|
	shard 01:    100 ( 20.0%) |########################################|
	shard 02:    100 ( 20.0%) |########################################|
	shard 03:    100 ( 20.0%) |########################################|
	shard 04:    100 ( 20.0%) |########################################|

Sequential ingest progression: 33% of keys
	shard 00:    100 ( 60.2%) |########################################|
	shard 01:     66 ( 39.8%) |##########################..............|
	shard 02:      0 (  0.0%) |........................................|
	shard 03:      0 (  0.0%) |........................................|
	shard 04:      0 (  0.0%) |........................................|

============ HASH ============

Sequential keys (overall)
	shard 00:    108 ( 21.6%) |##################################......|
	shard 01:    127 ( 25.4%) |########################################|
	shard 02:     94 ( 18.8%) |#############################...........|
	shard 03:     79 ( 15.8%) |########################................|
	shard 04:     92 ( 18.4%) |############################............|
```

Salted range (per-bucket view):

```text
Salted range: per-bucket distribution (buckets=8)
	bucket 00:     25 ( 12.5%) |###############################.........|
	bucket 01:     23 ( 11.5%) |############################............|
	bucket 02:     30 ( 15.0%) |#####################################...|
	bucket 03:     29 ( 14.5%) |####################################....|
	bucket 04:     28 ( 14.0%) |###################################.....|
	bucket 05:     20 ( 10.0%) |#########################...............|
	bucket 06:     13 (  6.5%) |################........................|
	bucket 07:     32 ( 16.0%) |########################################|
```
