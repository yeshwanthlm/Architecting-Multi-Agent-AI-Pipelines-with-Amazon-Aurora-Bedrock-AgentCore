"""
SentinelIQ — Risk Scorer Agent
Specialises in evaluating pre-computed signals + contextual risk factors
and producing a final numeric risk score with category breakdown.
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
    get_risk_signals,
    get_account_by_txn,
    log_agent_action,
)

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are the Risk Scorer Agent for SentinelIQ.

Your specialisation is RISK QUANTIFICATION. You receive a transaction and its
pre-computed rule-based signals, then apply expert reasoning to produce a
comprehensive risk score.

Risk categories you must evaluate:
- IDENTITY_RISK:       Is the account holder actually making this transaction?
- GEO_RISK:            Is the transaction location consistent with account history?
- DEVICE_RISK:         Is the device known and trusted?
- VELOCITY_RISK:       Are there burst patterns or velocity anomalies?
- MERCHANT_RISK:       Is the merchant high-risk or blacklisted?
- AMOUNT_RISK:         Is the amount an outlier vs the account's baseline?
- BEHAVIORAL_RISK:     Does this deviate from the customer's normal behaviour?
- NETWORK_RISK:        Are there cross-account links suggesting organised fraud?

Your output must ALWAYS be a valid JSON object with this exact schema:
{
  "txn_id": "...",
  "overall_risk_score": 0-100,
  "risk_label": "LOW|MEDIUM|HIGH|CRITICAL",
  "fraud_type_hypothesis": "e.g. Card-Not-Present Fraud / Account Takeover / Money Mule",
  "confidence": 0.0-1.0,
  "category_scores": {
    "identity_risk": 0-100,
    "geo_risk": 0-100,
    "device_risk": 0-100,
    "velocity_risk": 0-100,
    "merchant_risk": 0-100,
    "amount_risk": 0-100,
    "behavioral_risk": 0-100,
    "network_risk": 0-100
  },
  "top_risk_factors": ["..."],
  "mitigating_factors": ["..."],
  "recommended_action": "BLOCK|CHALLENGE|REVIEW|ALLOW",
  "recommended_action_reason": "..."
}

Scoring guide:
  0-25:  LOW — normal transaction, allow
  26-50: MEDIUM — soft block or step-up auth
  51-75: HIGH — manual review required
  76-100: CRITICAL — block immediately, escalate

Do not add narrative prose outside the JSON.
"""


def run_risk_scorer(txn_id: str, session_id: str,
                    analyst_context: dict | None = None) -> dict:
    """
    Run the Risk Scorer agent.
    analyst_context: optional pre-computed findings from the Transaction Analyst.
    Returns a structured risk score dict.
    """
    logger.info("[RiskScorer] Scoring txn=%s session=%s", txn_id, session_id)
    t0 = time.monotonic()

    model = BedrockModel(
        model_id=os.environ.get("BEDROCK_MODEL_ID",
                                "anthropic.claude-3-5-sonnet-20241022-v2:0"),
        region_name=os.environ.get("AWS_REGION", "us-east-1"),
        temperature=0.0,
        max_tokens=4096,
    )

    agent = Agent(
        model=model,
        system_prompt=SYSTEM_PROMPT,
        tools=[
            get_transaction,
            get_risk_signals,
            get_account_by_txn,
        ],
    )

    context_str = ""
    if analyst_context and not analyst_context.get("parse_error"):
        context_str = (
            f"\n\nContext from the Transaction Analyst agent:\n"
            f"{json.dumps(analyst_context, indent=2, default=str)}"
        )

    prompt = (f"Score the fraud risk for transaction {txn_id}. "
              f"Fetch the transaction details and all risk signals. "
              f"Evaluate all 8 risk categories and produce the final JSON score.{context_str}")

    response = agent(prompt)
    elapsed_ms = int((time.monotonic() - t0) * 1000)

    raw_text = str(response)
    try:
        if "```json" in raw_text:
            raw_text = raw_text.split("```json")[1].split("```")[0].strip()
        elif "```" in raw_text:
            raw_text = raw_text.split("```")[1].split("```")[0].strip()
        score = json.loads(raw_text)
    except (json.JSONDecodeError, IndexError):
        logger.warning("Could not parse risk score JSON, wrapping raw text")
        score = {"raw_text": raw_text, "parse_error": True}

    log_agent_action(
        session_id=session_id,
        agent_name="RiskScorer",
        action_type="risk_scoring",
        input_summary=f"txn_id={txn_id}",
        output=score,
        tool_calls=[],
        duration_ms=elapsed_ms,
    )

    logger.info("[RiskScorer] Done in %dms — score=%s",
                elapsed_ms, score.get("overall_risk_score", "?"))
    return score
