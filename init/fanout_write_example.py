# Example Python script for fanout-on-write in YCQL (Cassandra)
# Requires: pip install cassandra-driver

from cassandra.cluster import Cluster
from cassandra.query import SimpleStatement
import uuid
import datetime

KEYSPACE = "tinyinsta_ycql"

cluster = Cluster(["localhost"], port=9042)
session = cluster.connect(KEYSPACE)

def create_post(author_id, image_path, description):
    post_id = uuid.uuid4()
    created_at = datetime.datetime.utcnow()
    # Insert into posts
    session.execute(
        """
        INSERT INTO posts (id, user_id, image_path, description, created_at)
        VALUES (%s, %s, %s, %s, %s)
        """,
        (post_id, author_id, image_path, description, created_at)
    )
    # Get followers
    followers = session.execute(
        "SELECT follower_id FROM follows WHERE followee_id = %s", (author_id,)
    )
    # Fanout: insert into each follower's timeline
    for row in followers:
        session.execute(
            """
            INSERT INTO timeline (user_id, post_id, author_id, image_path, description, created_at)
            VALUES (%s, %s, %s, %s, %s, %s)
            """,
            (row.follower_id, post_id, author_id, image_path, description, created_at)
        )
    # Optionally, insert into author's own timeline
    session.execute(
        """
        INSERT INTO timeline (user_id, post_id, author_id, image_path, description, created_at)
        VALUES (%s, %s, %s, %s, %s, %s)
        """,
        (author_id, post_id, author_id, image_path, description, created_at)
    )
    print(f"Post {post_id} created and fanned out to timelines.")

# Example usage:
# create_post(uuid.UUID('...'), '/img/1.jpg', 'Hello world!')
