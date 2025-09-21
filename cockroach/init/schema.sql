-- Create database and tables for tinyinsta (CockroachDB)
CREATE DATABASE IF NOT EXISTS tinyinsta;
USE tinyinsta;

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username STRING UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS post (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id),
    content STRING NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS follower_followee (
    follower_id INT NOT NULL REFERENCES users(id),
    followee_id INT NOT NULL REFERENCES users(id),
    PRIMARY KEY (follower_id, followee_id)
);

-- Demo-friendly extended schema (Instagram-like)
-- Ensure optional column exists on users
ALTER TABLE users ADD COLUMN IF NOT EXISTS full_name STRING;

-- Posts (deterministic integer PK for easier SPLIT/SCATTER)
CREATE TABLE IF NOT EXISTS posts (
    id         INT PRIMARY KEY,
    author_id  INT NOT NULL REFERENCES users(id),
    caption    STRING,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Follows (composite primary key)
CREATE TABLE IF NOT EXISTS follows (
    follower_id INT NOT NULL REFERENCES users(id),
    followee_id INT NOT NULL REFERENCES users(id),
    created_at  TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (follower_id, followee_id)
);

-- Likes (composite primary key)
CREATE TABLE IF NOT EXISTS likes (
    user_id   INT NOT NULL REFERENCES users(id),
    post_id   INT NOT NULL REFERENCES posts(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (user_id, post_id)
);

-- Helpful secondary indexes
CREATE INDEX IF NOT EXISTS posts_author_created_idx ON posts (author_id, created_at DESC);
CREATE INDEX IF NOT EXISTS follows_by_follower_idx   ON follows (follower_id);
CREATE INDEX IF NOT EXISTS follows_by_followee_idx   ON follows (followee_id);
CREATE INDEX IF NOT EXISTS likes_by_post_idx         ON likes (post_id, created_at DESC);
CREATE INDEX IF NOT EXISTS likes_by_user_idx         ON likes (user_id, created_at DESC);
