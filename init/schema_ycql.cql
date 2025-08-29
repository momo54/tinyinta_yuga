// YCQL schema for fanout-on-write timeline (Cassandra style)
// This is CQL, not SQL!

CREATE KEYSPACE IF NOT EXISTS tinyinsta_ycql WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};

USE tinyinsta_ycql;

// Users
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY,
  username TEXT,
  password TEXT
);

// Posts
CREATE TABLE IF NOT EXISTS posts (
  id UUID PRIMARY KEY,
  user_id UUID,
  image_path TEXT,
  description TEXT,
  created_at TIMESTAMP
);

// Follows
CREATE TABLE IF NOT EXISTS follows (
  follower_id UUID,
  followee_id UUID,
  PRIMARY KEY (follower_id, followee_id)
);

// Timeline: fanout on write
// For each user, store the posts to show in their feed
CREATE TABLE IF NOT EXISTS timeline (
  user_id UUID,           // The owner of the timeline (the reader)
  post_id UUID,           // The post to show
  author_id UUID,         // Who wrote the post
  image_path TEXT,
  description TEXT,
  created_at TIMESTAMP,
  PRIMARY KEY (user_id, created_at, post_id)
) WITH CLUSTERING ORDER BY (created_at DESC);

// To insert a new post:
// 1. Insert into posts
// 2. For each follower, insert into timeline (fanout on write)
// 3. Optionally, insert into author's own timeline

// To get a user's feed:
// SELECT * FROM timeline WHERE user_id = ? LIMIT 50;
