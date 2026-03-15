"""
SentinelIQ — FastAPI Backend
Bridges the React UI to the Strands multi-agent pipeline.
Supports SSE streaming so the UI can show agent progress in real time.
"""
from __future__ import annotations
import asyncio
import json
import logging
import os
import sys
import time
import uuid
from contextlib import asynccontextmanager
from typing import AsyncIterator

import boto3
import psycopg2
import psycopg2.extras
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

# Make agents importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "agents"))

from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), "..", "agents", ".env"))

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s")
logger = logging.getLogger(__name__)


# ── DB helper ────────────────────────────────────────────────
def get_db_conn():
    import json as _json
    client = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION", "us-east-1"))
    secret = client.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])
    creds = _json.loads(secret["SecretString"])
    return psycopg2.connect(
        host=creds["host"], port=creds.get("port", 5432),
        dbname=creds["dbname"], user=creds["username"],
        password=creds["password"], sslmode="require", connect_timeout=10
    )


def db_query(sql: str, params: tuple = (), fetch: str = "all"):
    conn = get_db_conn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, params)
            conn.commit()
            if fetch == "all":
                return [dict(r) for r in cur.fetchall()]
            elif fetch == "one":
                r = cur.fetchone()
                return dict(r) if r else None
    finally:
        conn.close()


# ── FastAPI app ──────────────────────────────────────────────
app = FastAPI(title="SentinelIQ API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Pydantic models ───────────────────────────────────────────
class InvestigateRequest(BaseModel):
    txn_id: str
    case_number: str = ""


class VerdictRequest(BaseModel):
    case_number: str
    verdict: str
    reasoning: str
    risk_score: int


# ── Dashboard endpoints ───────────────────────────────────────

@app.get("/api/dashboard/stats")
async def dashboard_stats():
    """Summary stats for the dashboard header."""
    stats = db_query("""
        SELECT
            (SELECT COUNT(*) FROM fraud_cases WHERE status IN ('open','investigating','escalated')) AS open_cases,
            (SELECT COUNT(*) FROM fraud_cases WHERE status = 'escalated') AS critical_cases,
            (SELECT COUNT(*) FROM transactions WHERE status = 'flagged'
              AND txn_timestamp >= NOW() - INTERVAL '24 hours') AS flagged_24h,
            (SELECT COALESCE(SUM(amount),0) FROM transactions t
              JOIN fraud_cases fc ON fc.txn_id = t.txn_id
              WHERE fc.status IN ('confirmed','escalated')
                AND t.txn_timestamp >= NOW() - INTERVAL '30 days') AS fraud_amount_30d,
            (SELECT COUNT(*) FROM accounts WHERE status = 'under_review') AS accounts_under_review
    """, fetch="one")
    return stats or {}


@app.get("/api/cases")
async def list_cases(status: str = "", limit: int = 20):
    """List fraud cases with optional status filter."""
    where = "WHERE fc.status = %s" if status else "WHERE fc.status IN ('open','investigating','escalated')"
    params = (status, limit) if status else (limit,)
    return db_query(f"""
        SELECT fc.case_number, fc.fraud_type, fc.status, fc.risk_score,
               fc.ai_verdict, fc.opened_at, fc.assigned_to,
               a.customer_name, a.account_number, a.risk_tier,
               t.amount, t.currency, t.txn_id,
               t.country_code AS txn_country, t.merchant_name
        FROM fraud_cases fc
        JOIN accounts a ON a.account_id = fc.account_id
        LEFT JOIN transactions t ON t.txn_id = fc.txn_id
        {where}
        ORDER BY fc.risk_score DESC NULLS LAST, fc.opened_at DESC
        LIMIT %s
    """, params)


@app.get("/api/transactions/flagged")
async def flagged_transactions(limit: int = 15):
    """Recent flagged transactions."""
    return db_query("""
        SELECT t.txn_id, t.amount, t.currency, t.merchant_name,
               t.status, t.txn_timestamp, t.country_code, t.city,
               t.channel, t.is_international,
               a.customer_name, a.account_number, a.risk_tier,
               (SELECT COUNT(*) FROM risk_signals rs WHERE rs.txn_id = t.txn_id) AS signal_count
        FROM transactions t
        JOIN accounts a ON a.account_id = t.account_id
        WHERE t.status = 'flagged'
        ORDER BY t.txn_timestamp DESC
        LIMIT %s
    """, (limit,))


@app.get("/api/transactions/{txn_id}")
async def get_transaction(txn_id: str):
    """Full transaction detail."""
    row = db_query("""
        SELECT t.*, a.customer_name, a.account_number, a.risk_tier,
               a.avg_monthly_spend, a.last_login_at, a.last_login_device,
               m.category AS merchant_category, m.risk_score AS merchant_risk_score,
               m.is_blacklisted
        FROM transactions t
        JOIN accounts a ON a.account_id = t.account_id
        LEFT JOIN merchants m ON m.merchant_id = t.merchant_id
        WHERE t.txn_id = %s
    """, (txn_id,), fetch="one")
    if not row:
        raise HTTPException(404, f"Transaction {txn_id} not found")
    return row


@app.get("/api/signals/{txn_id}")
async def get_signals(txn_id: str):
    return db_query("""
        SELECT * FROM risk_signals WHERE txn_id = %s ORDER BY score DESC
    """, (txn_id,))


@app.get("/api/audit-log")
async def audit_log(limit: int = 20):
    return db_query("""
        SELECT session_id, agent_name, action_type, input_summary,
               duration_ms, created_at
        FROM agent_audit_log
        ORDER BY created_at DESC
        LIMIT %s
    """, (limit,))


# ── SSE Investigation endpoint ────────────────────────────────

@app.post("/api/investigate/stream")
async def investigate_stream(req: InvestigateRequest):
    """
    SSE endpoint — streams agent progress events as the investigation runs.
    The UI subscribes to this and animates agent steps in real time.
    """
    async def event_generator() -> AsyncIterator[str]:
        session_id = f"session-{uuid.uuid4().hex[:8]}"

        def sse(event: str, data: dict) -> str:
            return f"event: {event}\ndata: {json.dumps(data, default=str)}\n\n"

        yield sse("start", {"session_id": session_id, "txn_id": req.txn_id,
                             "message": "Investigation started"})
        await asyncio.sleep(0.1)

        try:
            # Run in thread pool so we don't block the event loop
            loop = asyncio.get_event_loop()

            # ── Analyst ─────────────────────────────────────
            yield sse("agent_start", {"agent": "TransactionAnalyst",
                                      "message": "Querying transaction history & velocity…"})
            analyst_findings = await loop.run_in_executor(
                None, lambda: _run_analyst(req.txn_id, session_id)
            )
            yield sse("agent_complete", {"agent": "TransactionAnalyst",
                                         "findings": analyst_findings})

            # ── Risk Scorer ──────────────────────────────────
            yield sse("agent_start", {"agent": "RiskScorer",
                                      "message": "Evaluating risk signals & scoring…"})
            risk_output = await loop.run_in_executor(
                None, lambda: _run_scorer(req.txn_id, session_id, analyst_findings)
            )
            yield sse("agent_complete", {"agent": "RiskScorer",
                                         "score": risk_output})

            # ── Supervisor ───────────────────────────────────
            yield sse("agent_start", {"agent": "Supervisor",
                                      "message": "Synthesizing findings and issuing verdict…"})
            verdict_data = await loop.run_in_executor(
                None, lambda: _run_supervisor_synthesis(
                    req.txn_id, req.case_number, session_id,
                    analyst_findings, risk_output
                )
            )
            yield sse("agent_complete", {"agent": "Supervisor",
                                         "verdict": verdict_data})

            yield sse("done", {"session_id": session_id,
                               "final_verdict": verdict_data.get("final_verdict"),
                               "final_risk_score": verdict_data.get("final_risk_score"),
                               "recommended_action": verdict_data.get("recommended_action")})

        except Exception as exc:
            logger.exception("Investigation failed")
            yield sse("error", {"message": str(exc)})

    return StreamingResponse(event_generator(),
                             media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache",
                                      "X-Accel-Buffering": "no"})


def _run_analyst(txn_id: str, session_id: str) -> dict:
    from transaction_analyst import run_transaction_analyst
    return run_transaction_analyst(txn_id, session_id)


def _run_scorer(txn_id: str, session_id: str, analyst_context: dict) -> dict:
    from risk_scorer import run_risk_scorer
    return run_risk_scorer(txn_id, session_id, analyst_context)


def _run_supervisor_synthesis(txn_id: str, case_number: str, session_id: str,
                               analyst: dict, scorer: dict) -> dict:
    from supervisor import investigate
    # We bypass the full parallel run since we already have sub-agent outputs
    report = investigate(txn_id, case_number)
    return report.to_dict()


# ── Non-streaming investigation (for CLI / testing) ──────────

@app.post("/api/investigate")
async def investigate_sync(req: InvestigateRequest):
    """Blocking investigation — returns full report. Use /stream for UI."""
    loop = asyncio.get_event_loop()
    from supervisor import investigate
    report = await loop.run_in_executor(
        None, lambda: investigate(req.txn_id, req.case_number)
    )
    return JSONResponse(report.to_dict())


# ── Static files (serve the UI) ───────────────────────────────
static_dir = os.path.join(os.path.dirname(__file__), "static")
if os.path.exists(static_dir):
    app.mount("/", StaticFiles(directory=static_dir, html=True), name="static")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=8000, reload=True)
