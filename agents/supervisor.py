"""
SentinelIQ — Supervisor Agent
The orchestrator. It:
  1. Receives a fraud investigation request
  2. Dispatches the Transaction Analyst and Risk Scorer sub-agents in parallel
  3. Synthesizes both outputs into a final verdict
  4. Writes the verdict back to the database
  5. Returns a complete investigation report

This is the primary entry point for the SentinelIQ system.
"""
from __future__ import annotations
import asyncio
import json
import logging
import os
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from typing import Any

from strands import Agent
from strands.models import BedrockModel

from mcp_client import update_case_verdict, log_agent_action, get_open_cases
from transaction_analyst import run_transaction_analyst
from risk_scorer import run_risk_scorer

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s"
)
logger = logging.getLogger(__name__)


SUPERVISOR_SYSTEM_PROMPT = """You are the Supervisor Agent for SentinelIQ, an advanced
multi-agent AI fraud detection platform.

You coordinate two specialist sub-agents:
- TransactionAnalyst: expert in structural DB analysis and behavioural patterns
- RiskScorer: expert in quantitative risk evaluation and fraud classification

Your role is to:
1. Review the outputs from both sub-agents
2. Identify any disagreements or complementary signals
3. Form the final, authoritative verdict
4. Provide clear, actionable recommendations for the fraud operations team

Your final verdict must be structured and include:
- An executive summary (2-3 sentences)
- The definitive fraud verdict and risk score
- Key evidence that drove the decision
- Recommended immediate actions (block account, reverse transaction, etc.)
- Any compliance/regulatory actions required (SAR filing, CTR, etc.)

Write professionally, as if briefing a senior fraud analyst.
"""


@dataclass
class InvestigationReport:
    """Complete investigation report from all three agents."""
    session_id: str
    txn_id: str
    case_number: str = ""
    analyst_findings: dict = field(default_factory=dict)
    risk_score_output: dict = field(default_factory=dict)
    supervisor_verdict: str = ""
    final_risk_score: int = 0
    final_verdict: str = "NEEDS_REVIEW"
    recommended_action: str = "REVIEW"
    total_duration_ms: int = 0
    agent_timeline: list[dict] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "session_id": self.session_id,
            "txn_id": self.txn_id,
            "case_number": self.case_number,
            "final_verdict": self.final_verdict,
            "final_risk_score": self.final_risk_score,
            "recommended_action": self.recommended_action,
            "supervisor_verdict": self.supervisor_verdict,
            "analyst_findings": self.analyst_findings,
            "risk_score_output": self.risk_score_output,
            "agent_timeline": self.agent_timeline,
            "total_duration_ms": self.total_duration_ms,
        }


def _run_parallel_agents(txn_id: str, session_id: str) -> tuple[dict, dict]:
    """
    Run the Transaction Analyst and Risk Scorer in parallel threads.
    Returns (analyst_findings, risk_score_output).
    """
    results: dict[str, Any] = {}
    timeline = []

    with ThreadPoolExecutor(max_workers=2, thread_name_prefix="sentinel-agent") as executor:
        futures = {
            executor.submit(run_transaction_analyst, txn_id, session_id): "analyst",
            executor.submit(run_risk_scorer, txn_id, session_id): "risk_scorer",
        }
        for future in as_completed(futures):
            name = futures[future]
            t_done = time.monotonic()
            try:
                results[name] = future.result()
                timeline.append({"agent": name, "status": "completed"})
                logger.info("[Supervisor] Sub-agent '%s' completed", name)
            except Exception as exc:
                logger.error("[Supervisor] Sub-agent '%s' failed: %s", name, exc)
                results[name] = {"error": str(exc)}
                timeline.append({"agent": name, "status": "failed", "error": str(exc)})

    return results.get("analyst", {}), results.get("risk_scorer", {})


def investigate(txn_id: str, case_number: str = "") -> InvestigationReport:
    """
    Full investigation pipeline — this is the main public API.

    Args:
        txn_id:      The transaction ID to investigate
        case_number: Optional case number to write verdict back to DB

    Returns:
        InvestigationReport with all findings and verdict
    """
    session_id = f"session-{uuid.uuid4().hex[:12]}"
    report = InvestigationReport(session_id=session_id, txn_id=txn_id,
                                 case_number=case_number)
    t_start = time.monotonic()

    logger.info("=" * 60)
    logger.info("[Supervisor] Investigation START txn=%s session=%s", txn_id, session_id)
    logger.info("=" * 60)

    # ── Step 1: Dispatch sub-agents in parallel ──────────────
    logger.info("[Supervisor] Dispatching TransactionAnalyst + RiskScorer in parallel…")
    analyst_findings, risk_score_output = _run_parallel_agents(txn_id, session_id)
    report.analyst_findings = analyst_findings
    report.risk_score_output = risk_score_output

    # ── Step 2: Extract numeric score for DB write ────────────
    raw_score = risk_score_output.get("overall_risk_score", 50)
    try:
        report.final_risk_score = int(raw_score)
    except (ValueError, TypeError):
        report.final_risk_score = 50

    report.recommended_action = risk_score_output.get("recommended_action", "REVIEW")
    report.case_number = case_number

    # ── Step 3: Supervisor synthesis ──────────────────────────
    logger.info("[Supervisor] Synthesizing findings…")
    model = BedrockModel(
        model_id=os.environ.get("BEDROCK_MODEL_ID",
                                "anthropic.claude-3-5-sonnet-20241022-v2:0"),
        region_name=os.environ.get("AWS_REGION", "us-east-1"),
        temperature=0.1,
        max_tokens=2048,
    )

    supervisor_agent = Agent(
        model=model,
        system_prompt=SUPERVISOR_SYSTEM_PROMPT,
    )

    synthesis_prompt = f"""
You have received outputs from two specialist agents investigating transaction {txn_id}.

═══════════════════════════════════════════
TRANSACTION ANALYST FINDINGS:
{json.dumps(analyst_findings, indent=2, default=str)}

═══════════════════════════════════════════
RISK SCORER OUTPUT:
{json.dumps(risk_score_output, indent=2, default=str)}

═══════════════════════════════════════════

Based on these combined findings, provide your final investigation report.
Include: executive summary, verdict, evidence summary, recommended actions,
and any compliance requirements.
"""

    supervisor_response = supervisor_agent(synthesis_prompt)
    report.supervisor_verdict = str(supervisor_response)

    # ── Step 4: Map to verdict enum ───────────────────────────
    score = report.final_risk_score
    if score >= 85:
        report.final_verdict = "CONFIRMED_FRAUD"
    elif score >= 65:
        report.final_verdict = "LIKELY_FRAUD"
    elif score >= 45:
        report.final_verdict = "SUSPICIOUS"
    elif score >= 20:
        report.final_verdict = "NEEDS_REVIEW"
    else:
        report.final_verdict = "LEGITIMATE"

    # ── Step 5: Write verdict to DB ───────────────────────────
    if case_number:
        logger.info("[Supervisor] Writing verdict to DB case=%s", case_number)
        try:
            update_case_verdict(
                case_number=case_number,
                verdict=report.final_verdict,
                reasoning=report.supervisor_verdict[:2000],  # DB field limit
                risk_score=report.final_risk_score,
                agent_name="AI-Supervisor"
            )
        except Exception as exc:
            logger.warning("[Supervisor] Could not write verdict to DB: %s", exc)

    # ── Step 6: Audit the supervisor itself ──────────────────
    report.total_duration_ms = int((time.monotonic() - t_start) * 1000)
    report.agent_timeline = [
        {"agent": "TransactionAnalyst", "status": "completed" if not analyst_findings.get("error") else "failed"},
        {"agent": "RiskScorer",         "status": "completed" if not risk_score_output.get("error") else "failed"},
        {"agent": "Supervisor",         "status": "completed"},
    ]

    log_agent_action(
        session_id=session_id,
        agent_name="Supervisor",
        action_type="investigation_complete",
        input_summary=f"txn_id={txn_id} case={case_number}",
        output={"verdict": report.final_verdict, "risk_score": report.final_risk_score},
        tool_calls=[{"agent": a["agent"]} for a in report.agent_timeline],
        duration_ms=report.total_duration_ms,
    )

    logger.info("=" * 60)
    logger.info("[Supervisor] VERDICT=%s SCORE=%d DURATION=%dms",
                report.final_verdict, report.final_risk_score, report.total_duration_ms)
    logger.info("=" * 60)

    return report


# ── CLI entry point ───────────────────────────────────────────
if __name__ == "__main__":
    import argparse
    from dotenv import load_dotenv

    load_dotenv()

    parser = argparse.ArgumentParser(description="SentinelIQ — Multi-Agent Fraud Investigation")
    parser.add_argument("--txn-id",     required=True,  help="Transaction ID to investigate")
    parser.add_argument("--case-number",default="",     help="Case number for DB write-back")
    parser.add_argument("--output",     default="json", choices=["json", "text"],
                        help="Output format")
    args = parser.parse_args()

    report = investigate(args.txn_id, args.case_number)

    if args.output == "json":
        print(json.dumps(report.to_dict(), indent=2, default=str))
    else:
        print(f"\n{'='*60}")
        print(f"  SENTINELIQ INVESTIGATION REPORT")
        print(f"{'='*60}")
        print(f"  Transaction:  {report.txn_id}")
        print(f"  Session:      {report.session_id}")
        print(f"  Verdict:      {report.final_verdict}")
        print(f"  Risk Score:   {report.final_risk_score}/100")
        print(f"  Action:       {report.recommended_action}")
        print(f"  Duration:     {report.total_duration_ms}ms")
        print(f"{'='*60}")
        print(f"\n{report.supervisor_verdict}")
