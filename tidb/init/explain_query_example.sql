-- EXPLAIN ANALYZE for the feed query in TiDB
SET @userId = 1;
EXPLAIN ANALYZE
SELECT p.*
FROM post p
WHERE p.user_id = @userId
   OR p.user_id IN (
        SELECT f.followee_id FROM follower_followee f WHERE f.follower_id = @userId
      )
ORDER BY p.created_at DESC
LIMIT 50;
