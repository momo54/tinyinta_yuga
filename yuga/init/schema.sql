-- Schema definition for tinyinsta_yuga (Yugabyte YSQL)
DROP TABLE IF EXISTS follower_followee CASCADE;
DROP TABLE IF EXISTS post CASCADE;
DROP TABLE IF EXISTS users CASCADE;

CREATE TABLE users (
	id BIGSERIAL PRIMARY KEY,
	username VARCHAR(255) UNIQUE NOT NULL,
	password VARCHAR(255) NOT NULL
);

CREATE TABLE post (
	id BIGSERIAL PRIMARY KEY,
	user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	image_path VARCHAR(255) NOT NULL,
	description VARCHAR(255),
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE follower_followee (
	id BIGSERIAL PRIMARY KEY,
	follower_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	followee_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX ON post (user_id, created_at DESC);
CREATE INDEX ON follower_followee (follower_id, followee_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_follow ON follower_followee(follower_id, followee_id);
