-- Explain analyze with distributed counters for the timeline query
\set userId 1
EXPLAIN (ANALYZE, DIST)
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
