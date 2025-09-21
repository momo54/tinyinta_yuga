-- Create database and schema for TiDB (MySQL compatible)
DROP DATABASE IF EXISTS tinyinsta;
CREATE DATABASE tinyinsta CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE tinyinsta;

-- Users
CREATE TABLE users (
  id BIGINT PRIMARY KEY,
  username VARCHAR(100) NOT NULL UNIQUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Posts
CREATE TABLE post (
  id BIGINT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  description TEXT,
  image_path VARCHAR(255),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_post_user_created (user_id, created_at DESC),
  CONSTRAINT fk_post_user FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Follows
CREATE TABLE follower_followee (
  follower_id BIGINT NOT NULL,
  followee_id BIGINT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(follower_id, followee_id),
  INDEX idx_followee (followee_id),
  CONSTRAINT chk_no_self_follow CHECK (follower_id <> followee_id),
  CONSTRAINT fk_follower FOREIGN KEY (follower_id) REFERENCES users(id),
  CONSTRAINT fk_followee FOREIGN KEY (followee_id) REFERENCES users(id)
);
