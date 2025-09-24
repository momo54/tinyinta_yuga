#!/usr/bin/env python3
"""
Sharding demo: range vs hash (no database required)

Illustrates how keys are assigned to shards using:
- range sharding (by key ranges)
- hash sharding (by SHA1(key) % N)

Also simulates sequential ingest progression to show potential hotspots.

Usage examples:
  python3 sharding_demo.py --strategy range --shards 4 --n-keys 1000 --splits 250,500,750
  python3 sharding_demo.py --strategy hash  --shards 4 --n-keys 1000
  python3 sharding_demo.py --compare --shards 5 --n-keys 500

"""
import argparse
import hashlib
import math
import random
from typing import List, Dict, Iterable, Tuple


def sha1_mod(key: int, shards: int) -> int:
    h = hashlib.sha1(str(key).encode("utf-8")).hexdigest()
    return int(h, 16) % shards


def assign_range(key: int, splits: List[int]) -> int:
    """Return shard index based on ascending split points.
    splits = [s1, s2, ..., s_{n-1}] for n shards.
    shard 0: (-inf, s1], shard 1: (s1, s2], ..., last: (s_{n-1}, +inf)
    We'll treat as left-closed for 0 and right-closed for others for simplicity.
    """
    for i, s in enumerate(splits):
        if key <= s:
            return i
    return len(splits)  # last shard


def salt_of(key: int, buckets: int) -> int:
    if buckets <= 1:
        return 0
    # Deterministic bucket from hash(key)
    h = hashlib.sha1(str(key).encode("utf-8")).hexdigest()
    return int(h, 16) % buckets


def histogram(assignments: Iterable[int], shards: int) -> List[int]:
    counts = [0] * shards
    for s in assignments:
        counts[s] += 1
    return counts


def ascii_bar(count: int, max_count: int, width: int = 40) -> str:
    if max_count <= 0:
        return ""
    filled = int(width * (count / max_count))
    return "#" * filled + "." * (width - filled)


def print_hist(title: str, counts: List[int], label: str = "shard"):
    total = sum(counts)
    max_c = max(counts) if counts else 0
    print(f"\n{title}")
    for i, c in enumerate(counts):
        pct = (100.0 * c / total) if total else 0.0
        print(f"  {label} {i:02d}: {c:6d} ({pct:5.1f}%) |{ascii_bar(c, max_c)}|")


def gen_keys(n: int, mode: str = "sequential", key_min: int = 1) -> List[int]:
    if mode == "sequential":
        return list(range(key_min, key_min + n))
    elif mode == "random":
        return [random.randint(key_min, key_min + n - 1) for _ in range(n)]
    else:
        raise ValueError("mode must be 'sequential' or 'random'")


def even_splits(n_shards: int, max_key: int, min_key: int = 1) -> List[int]:
    if n_shards <= 1:
        return []
    step = (max_key - min_key + 1) / n_shards
    # Create n_shards-1 split points
    splits = [math.floor(min_key - 1 + step * (i + 1)) for i in range(n_shards - 1)]
    # Ensure strictly increasing
    for i in range(1, len(splits)):
        if splits[i] <= splits[i - 1]:
            splits[i] = splits[i - 1] + 1
    return splits


def simulate(strategy: str, shards: int, n_keys: int, splits: List[int] | None) -> Dict[str, List[int]]:
    result: Dict[str, List[int]] = {}
    # Sequential overall
    seq_keys = gen_keys(n_keys, mode="sequential")
    if strategy == "hash":
        assigns = [sha1_mod(k, shards) for k in seq_keys]
    else:
        assert splits is not None
        assigns = [assign_range(k, splits) for k in seq_keys]
    result["sequential_all"] = histogram(assigns, shards)

    # Random overall
    rnd_keys = gen_keys(n_keys, mode="random")
    if strategy == "hash":
        assigns = [sha1_mod(k, shards) for k in rnd_keys]
    else:
        assert splits is not None
        assigns = [assign_range(k, splits) for k in rnd_keys]
    result["random_all"] = histogram(assigns, shards)

    return result


def simulate_progress(strategy: str, shards: int, n_keys: int, splits: List[int] | None, steps: int = 5) -> List[Tuple[int, List[int]]]:
    """Sequential ingest progress: after t% of keys inserted, what's the shard distribution so far?"""
    seq_keys = gen_keys(n_keys, mode="sequential")
    out: List[Tuple[int, List[int]]] = []
    for frac in range(1, steps + 1):
        upto = max(1, (n_keys * frac) // steps)
        part = seq_keys[:upto]
        if strategy == "hash":
            assigns = [sha1_mod(k, shards) for k in part]
        else:
            assert splits is not None
            assigns = [assign_range(k, splits) for k in part]
        out.append((int(100 * frac / steps), histogram(assigns, shards)))
    return out


def simulate_progress_range_autosplit(n_keys: int, initial_splits: List[int], steps: int = 5, threshold: float = 0.4, autosplit_where: str = "current") -> List[Tuple[int, List[int], List[int]]]:
    """
    Simulate sequential ingest with dynamic auto-splitting for range sharding.
    - Starts with given split points.
    - As keys 1..N arrive, if the LAST range accumulates more than `threshold` of inserted keys so far,
      we create a split at the current key, producing a new last range.
    - Returns a progression list of (percent, counts_per_range, current_splits).

    Notes:
    - The number of ranges grows over time. We report per-range counts (labelled as 'range').
    - This models a simple split policy focusing on the hotspot (tail) in monotonic inserts.
    """
    if threshold <= 0 or threshold >= 1:
        raise ValueError("threshold must be between 0 and 1 (e.g., 0.4)")

    splits = list(initial_splits)
    # counts per range = len(splits)+1
    counts: List[int] = [0] * (len(splits) + 1)
    out: List[Tuple[int, List[int], List[int]]] = []

    checkpoints = [max(1, (n_keys * frac) // steps) for frac in range(1, steps + 1)]
    checkpoint_set = set(checkpoints)

    for i in range(1, n_keys + 1):
        # assign to current range
        idx = assign_range(i, splits)
        # ensure counts size matches splits
        if len(counts) != len(splits) + 1:
            # reinit counts shape if needed (shouldn't happen here)
            counts = counts + [0] * (len(splits) + 1 - len(counts))
        counts[idx] += 1

        # auto-split only considers the last range (tail hotspot in sequential ingest)
        last_idx = len(splits)  # index of last range
        total_so_far = i
        if idx == last_idx and total_so_far > 1:
            if counts[last_idx] / total_so_far > threshold:
                # Determine split point
                last_start = (splits[-1] + 1) if splits else 1
                split_key = i if autosplit_where == "current" else (last_start + i) // 2
                # Only split if strictly increasing
                if not splits or split_key > splits[-1]:
                    splits.append(split_key)
                    counts.append(0)

        if i in checkpoint_set:
            pct = int(round(100 * i / n_keys))
            out.append((pct, counts.copy(), splits.copy()))

    return out


def simulate_progress_range_autosplit_with_nodes(
    n_keys: int,
    initial_splits: List[int],
    steps: int = 5,
    threshold: float = 0.4,
    autosplit_where: str = "current",
    nodes: int = 0,
    rebalance_after_split: bool = False,
) -> List[Tuple[int, List[int], List[int], List[int]]]:
    """
    Auto-split progression with range-to-node mapping and optional rebalance.
    - Maintains counts per range and per node.
    - On split of the last range:
        * left subrange keeps its node
        * right subrange goes to either the same node or to the least-loaded node if rebalance_after_split is True
    Returns a list of (percent, counts_per_range, splits, counts_per_node).
    """
    if threshold <= 0 or threshold >= 1:
        raise ValueError("threshold must be between 0 and 1 (e.g., 0.4)")
    if nodes <= 0:
        nodes = 0

    splits = list(initial_splits)
    counts: List[int] = [0] * (len(splits) + 1)
    node_counts: List[int] = [0] * nodes if nodes > 0 else []
    # range -> node mapping
    range_nodes: List[int] = []
    if nodes > 0:
        # Round-robin initial assignment across existing ranges
        rngs = len(splits) + 1
        range_nodes = [(i % nodes) for i in range(rngs)]
    out: List[Tuple[int, List[int], List[int], List[int]]] = []

    checkpoints = [max(1, (n_keys * frac) // steps) for frac in range(1, steps + 1)]
    checkpoint_set = set(checkpoints)

    for i in range(1, n_keys + 1):
        idx = assign_range(i, splits)
        # ensure structure sizes match
        if len(counts) != len(splits) + 1:
            counts = counts + [0] * (len(splits) + 1 - len(counts))
        if nodes > 0 and len(range_nodes) != len(splits) + 1:
            # extend mapping for new range(s)
            range_nodes += [range_nodes[-1] if range_nodes else 0] * ((len(splits) + 1) - len(range_nodes))

        counts[idx] += 1
        if nodes > 0:
            node = range_nodes[idx]
            node_counts[node] += 1

        last_idx = len(splits)
        total_so_far = i
        if idx == last_idx and total_so_far > 1:
            if counts[last_idx] / total_so_far > threshold:
                last_start = (splits[-1] + 1) if splits else 1
                split_key = i if autosplit_where == "current" else (last_start + i) // 2
                if not splits or split_key > splits[-1]:
                    # perform split
                    splits.append(split_key)
                    counts.append(0)
                    if nodes > 0:
                        # left stays on current node
                        left_node = range_nodes[last_idx] if range_nodes else 0
                        # right node choice
                        if rebalance_after_split:
                            # least loaded node by node_counts
                            target = min(range(nodes), key=lambda n: node_counts[n]) if nodes > 0 else left_node
                        else:
                            target = left_node
                        range_nodes.append(target)
                        # Note: we do not reassign old ranges or retroactively move counts

        if i in checkpoint_set:
            pct = int(round(100 * i / n_keys))
            out.append((pct, counts.copy(), splits.copy(), node_counts.copy() if nodes > 0 else []))

    return out


def simulate_range_with_salt(n_keys: int, splits: List[int], buckets: int) -> Dict[str, List[int]]:
    """
    Simulate range sharding using composite key (salt, key):
    - Routing is by (salt, key) in lexicographic order, with splits defined on the key only.
    - We show two distributions:
        * per_range: counts per range (like before)
        * per_bucket: counts per salt bucket (to show write spreading)
    """
    keys = gen_keys(n_keys, mode="sequential")
    per_range = [0] * (len(splits) + 1)
    per_bucket = [0] * max(1, buckets)

    for k in keys:
        b = salt_of(k, buckets)
        # Range routing uses key value for boundary, but because salt is the first sort key,
        # writes are interleaved across buckets; we simply reflect that by counting per bucket
        r = assign_range(k, splits)
        per_range[r] += 1
        per_bucket[b] += 1

    return {"per_range": per_range, "per_bucket": per_bucket}


def simulate_progress_range_with_salt(n_keys: int, splits: List[int], buckets: int, steps: int = 5) -> List[Tuple[int, List[int], List[int]]]:
    """Progression for salted range: report counts per range and per bucket over time."""
    keys = gen_keys(n_keys, mode="sequential")
    per_range = [0] * (len(splits) + 1)
    per_bucket = [0] * max(1, buckets)
    out: List[Tuple[int, List[int], List[int]]] = []

    checkpoints = [max(1, (n_keys * frac) // steps) for frac in range(1, steps + 1)]
    checkpoint_set = set(checkpoints)

    for i, k in enumerate(keys, start=1):
        b = salt_of(k, buckets)
        r = assign_range(k, splits)
        per_range[r] += 1
        per_bucket[b] += 1
        if i in checkpoint_set:
            pct = int(round(100 * i / n_keys))
            out.append((pct, per_range.copy(), per_bucket.copy()))

    return out


def parse_splits(text: str) -> List[int]:
    parts = [int(p.strip()) for p in text.split(",") if p.strip()]
    if sorted(parts) != parts:
        raise ValueError("splits must be ascending integers")
    return parts


def main():
    ap = argparse.ArgumentParser(description="Sharding demo: range vs hash")
    ap.add_argument("--strategy", choices=["range", "hash"], default="hash", help="Sharding strategy")
    ap.add_argument("--shards", type=int, default=4, help="Number of shards")
    ap.add_argument("--n-keys", type=int, default=1000, help="Number of keys to simulate (1..N)")
    ap.add_argument("--splits", type=str, default="", help="Comma-separated split points for range (n-1 points)")
    ap.add_argument("--compare", action="store_true", help="Show both strategies side by side")
    ap.add_argument("--auto-split", action="store_true", help="Enable dynamic auto-splitting for range sharding during sequential ingest progression")
    ap.add_argument("--autosplit-threshold", type=float, default=0.4, help="Fraction of inserted keys in the last range that triggers a split (0<val<1), default 0.4")
    ap.add_argument("--autosplit-where", choices=["current", "middle"], default="current", help="Where to split the last range when threshold is hit: at current key or middle of last range")
    ap.add_argument("--salt-buckets", type=int, default=0, help="When >0 and strategy=range: simulate salted keys with this many buckets; reports per-range and per-bucket distributions")
    ap.add_argument("--nodes", type=int, default=0, help="When >0 and using range+auto-split: number of nodes to show per-node load distribution")
    ap.add_argument("--rebalance-after-split", action="store_true", help="When using range+auto-split with nodes>0: assign the new right range to the least loaded node")
    ap.add_argument("--progress-steps", type=int, default=5, help="Steps to show for sequential ingest progression")
    args = ap.parse_args()

    if args.shards < 1:
        raise SystemExit("--shards must be >= 1")

    if args.compare:
        # Determine splits automatically for range based on uniform domain
        splits = even_splits(args.shards, args.n_keys)
        print(f"Auto range splits for compare: {splits}")
        for strat in ("range", "hash"):
            print("\n" + "=" * 12 + f" {strat.upper()} " + "=" * 12)
            sim = simulate(strat, args.shards, args.n_keys, splits if strat == "range" else None)
            print_hist("Sequential keys (overall)", sim["sequential_all"], label="shard")
            print_hist("Random keys (overall)", sim["random_all"], label="shard")

            # Ingest progression (sequential only)
            if strat == "range" and args.auto_split:
                if args.nodes and args.nodes > 0:
                    prog2n = simulate_progress_range_autosplit_with_nodes(
                        args.n_keys, splits, steps=args.progress_steps,
                        threshold=args.autosplit_threshold, autosplit_where=args.autosplit_where,
                        nodes=args.nodes, rebalance_after_split=args.rebalance_after_split,
                    )
                    for pct, counts, sp, nodec in prog2n:
                        print_hist(f"Sequential ingest progression (auto-split): {pct}% of keys | splits={sp}", counts, label="range")
                        print_hist(f"Per-node load (nodes={args.nodes})", nodec, label="node")
                else:
                    prog2 = simulate_progress_range_autosplit(args.n_keys, splits, steps=args.progress_steps, threshold=args.autosplit_threshold, autosplit_where=args.autosplit_where)
                    for pct, counts, sp in prog2:
                        print_hist(f"Sequential ingest progression (auto-split): {pct}% of keys | splits={sp}", counts, label="range")
            else:
                prog = simulate_progress(strat, args.shards, args.n_keys, splits if strat == "range" else None, steps=args.progress_steps)
                for pct, counts in prog:
                    print_hist(f"Sequential ingest progression: {pct}% of keys", counts, label="shard")
        return

    # Single strategy mode
    splits = None
    if args.strategy == "range":
        splits = parse_splits(args.splits) if args.splits else even_splits(args.shards, args.n_keys)
        if len(splits) != max(0, args.shards - 1):
            raise SystemExit(f"For {args.shards} shards, need {args.shards - 1} split points (got {len(splits)}): {splits}")
        print(f"Range splits: {splits}")

    sim = simulate(args.strategy, args.shards, args.n_keys, splits)
    print_hist("Sequential keys (overall)", sim["sequential_all"], label="shard")
    print_hist("Random keys (overall)", sim["random_all"], label="shard")

    if args.strategy == "range":
        if args.salt_buckets and args.salt_buckets > 0:
            salted = simulate_range_with_salt(args.n_keys, splits, args.salt_buckets)
            print_hist(f"Salted range: per-range distribution (buckets={args.salt_buckets})", salted["per_range"], label="range")
            print_hist(f"Salted range: per-bucket distribution (buckets={args.salt_buckets})", salted["per_bucket"], label="bucket")
            prog_s = simulate_progress_range_with_salt(args.n_keys, splits, args.salt_buckets, steps=args.progress_steps)
            for pct, pr, pb in prog_s:
                print_hist(f"Salted range progression: {pct}% of keys (per-range)", pr, label="range")
                print_hist(f"Salted range progression: {pct}% of keys (per-bucket)", pb, label="bucket")
        elif args.auto_split:
            if args.nodes and args.nodes > 0:
                prog2n = simulate_progress_range_autosplit_with_nodes(
                    args.n_keys, splits, steps=args.progress_steps,
                    threshold=args.autosplit_threshold, autosplit_where=args.autosplit_where,
                    nodes=args.nodes, rebalance_after_split=args.rebalance_after_split,
                )
                for pct, counts, sp, nodec in prog2n:
                    print_hist(f"Sequential ingest progression (auto-split): {pct}% of keys | splits={sp}", counts, label="range")
                    print_hist(f"Per-node load (nodes={args.nodes})", nodec, label="node")
            else:
                prog2 = simulate_progress_range_autosplit(args.n_keys, splits, steps=args.progress_steps, threshold=args.autosplit_threshold, autosplit_where=args.autosplit_where)
                for pct, counts, sp in prog2:
                    print_hist(f"Sequential ingest progression (auto-split): {pct}% of keys | splits={sp}", counts, label="range")
        else:
            prog = simulate_progress(args.strategy, args.shards, args.n_keys, splits, steps=args.progress_steps)
            for pct, counts in prog:
                print_hist(f"Sequential ingest progression: {pct}% of keys", counts, label="shard")


if __name__ == "__main__":
    main()
