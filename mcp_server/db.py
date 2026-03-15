"""
SentinelIQ MCP Server — Database Connection
Fetches credentials from Secrets Manager and maintains a connection pool.
Uses psycopg2 with RDS IAM auth support.
"""
import json
import logging
import os
from functools import lru_cache

import boto3
import psycopg2
import psycopg2.extras
from psycopg2.pool import ThreadedConnectionPool

logger = logging.getLogger(__name__)

_pool: ThreadedConnectionPool | None = None


@lru_cache(maxsize=1)
def _get_credentials() -> dict:
    """Fetch DB credentials from Secrets Manager (cached per Lambda container)."""
    client = boto3.client("secretsmanager", region_name=os.environ["REGION"])
    secret = client.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])
    return json.loads(secret["SecretString"])


def get_pool() -> ThreadedConnectionPool:
    global _pool
    if _pool is None or _pool.closed:
        creds = _get_credentials()
        _pool = ThreadedConnectionPool(
            minconn=1,
            maxconn=5,
            host=creds["host"],
            port=creds.get("port", 5432),
            dbname=creds["dbname"],
            user=creds["username"],
            password=creds["password"],
            sslmode="require",
            connect_timeout=10,
            options="-c statement_timeout=25000",  # 25-second query timeout
        )
        logger.info("Connection pool created — host=%s db=%s", creds["host"], creds["dbname"])
    return _pool


def query(sql: str, params: tuple = (), fetch: str = "all") -> list[dict] | dict | None:
    """
    Execute a SQL query and return results as dicts.
    fetch: 'all' | 'one' | 'none'
    """
    pool = get_pool()
    conn = pool.getconn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, params)
            conn.commit()
            if fetch == "all":
                return [dict(r) for r in cur.fetchall()]
            elif fetch == "one":
                row = cur.fetchone()
                return dict(row) if row else None
            return None
    except Exception:
        conn.rollback()
        raise
    finally:
        pool.putconn(conn)
