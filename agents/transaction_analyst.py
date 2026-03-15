"""
SentinelIQ — Transaction Analyst Agent
Specialises in structural DB analysis: transaction history, velocity,
cross-account fingerprinting, and behavioural baselines.
"""
from __future__ import annotations
import json
import logging
import os
import time

from strands import Agent
from strands.models import BedrockModel

from mcp_client import (
    get_transaction,
    get_account_history,
    get_account_by_txn,
    velocity_check,
    get_similar_transactions,
    log_agent_action,
)

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are the Transaction Analyst Agent for SentinelIQ, an AI-powered
financial fraud detection platform.

Your specialisation is STRUCTURAL DATA ANALYSIS. When given a transaction ID or case,
you must:

1. Retrieve the full transaction details
2. Pull the account's recent history (last 30 days) to establish a spending baseline
3. Run a velocity check across multiple time windows (15min, 1hr, 24hr)
4. Search for cross-account connections via shared IPs, devices, or amounts
5. Compile a structured findings report

Your output must ALWAYS be a valid JSON object with this exact schema:
{
  "txn_id": "...",
  "account_id": "...",
  "customer_name": "...",
  "analyst_findings": {
    "transaction_summary": "...",
    "behavioural_deviation": "low|medium|high|critical",
    "velocity_summary": "...",
    "cross_account_links": [],
    "geo_analysis": "...",
    "device_analysis": "...",
    "key_anomalies": ["...", "..."],
    "baseline_comparison": "..."
  },
  "raw_signals_count": 0,
  "recommended_escalation": true|false
}

Be thorough but concise. Do not add narrative prose outside the JSON.
"""


def run_transaction_analyst(txn_id: str, session_id: str) -> dict:
    """
    Run the Transaction Analyst agent against a transaction.
    Returns a structured findings dict.
    """
    logger.info("[TransactionAnalyst] Starting analysis for txn=%s session=%s",
                txn_id, session_id)
    t0 = time.monotonic()

    model = BedrockModel(
        model_id=os.environ.get("BEDROCK_MODEL_ID",
                                "anthropic.claude-3-5-sonnet-20241022-v2:0"),
        region_name=os.environ.get("AWS_REGION", "us-east-1"),
        temperature=0.0,   # Deterministic for fraud analysis
        max_tokens=4096,
    )

    agent = Agent(
        model=model,
        system_prompt=SYSTEM_PROMPT,
        tools=[
            get_transaction,
            get_account_history,
            get_account_by_txn,
            velocity_check,
            get_similar_transactions,
        ],
    )

    prompt = (f"Investigate transaction {txn_id}. "
              f"Check velocity windows of 15, 60, and 1440 minutes. "
              f"Search for cross-account links. Return JSON findings.")

    response = agent(prompt)
    elapsed_ms = int((time.monotonic() - t0) * 1000)

    # Parse the agent's JSON output
    raw_text = str(response)
    try:
        # Extract JSON block if wrapped in markdown
        if "```json" in raw_text:
            raw_text = raw_text.split("```json")[1].split("```")[0].strip()
        elif "```" in raw_text:
            raw_text = raw_text.split("```")[1].split("```")[0].strip()
        findings = json.loads(raw_text)
    except (json.JSONDecodeError, IndexError):
        logger.warning("Could not parse analyst JSON, wrapping raw text")
        findings = {"raw_text": raw_text, "parse_error": True}

    # Audit log
    log_agent_action(
        session_id=session_id,
        agent_name="TransactionAnalyst",
        action_type="full_analysis",
        input_summary=f"txn_id={txn_id}",
        output=findings,
        tool_calls=getattr(agent, "_tool_call_history", []),
        duration_ms=elapsed_ms,
    )

    logger.info("[TransactionAnalyst] Done in %dms", elapsed_ms)
    return findings
