"""
SentinelIQ — MCP Client
Wraps the Lambda MCP server so Strands can treat it as a tool provider.
Calls the Lambda Function URL using SigV4 (IAM auth).
"""
from __future__ import annotations
import json
import logging
import os
import time

import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
import requests

logger = logging.getLogger(__name__)


class MCPLambdaClient:
    """
    Thin client that speaks the MCP JSON-RPC protocol over a Lambda Function URL.
    Handles SigV4 signing so the Function URL can use AWS_IAM auth.
    """

    def __init__(self):
        self.function_url = os.environ["MCP_FUNCTION_URL"].rstrip("/")
        self.region = os.environ.get("AWS_REGION", "us-east-1")
        session = boto3.Session()
        self._credentials = session.get_credentials()
        self._session = requests.Session()
        self._tools_cache: list[dict] | None = None

    def _call(self, method: str, params: dict | None = None) -> dict:
        payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method,
                              "params": params or {}}).encode()

        request = AWSRequest(method="POST", url=self.function_url,
                             data=payload, headers={"Content-Type": "application/json"})
        SigV4Auth(self._credentials, "lambda", self.region).add_auth(request)

        resp = self._session.post(
            self.function_url,
            data=payload,
            headers=dict(request.headers),
            timeout=60,
        )
        resp.raise_for_status()
        body = resp.json()
        if "error" in body:
            raise RuntimeError(f"MCP error: {body['error']}")
        return body.get("result", {})

    def list_tools(self) -> list[dict]:
        if self._tools_cache is None:
            result = self._call("tools/list")
            self._tools_cache = result.get("tools", [])
        return self._tools_cache

    def call_tool(self, name: str, arguments: dict) -> str:
        """Invoke a tool and return its text result."""
        t0 = time.monotonic()
        result = self._call("tools/call", {"name": name, "arguments": arguments})
        elapsed = int((time.monotonic() - t0) * 1000)
        content = result.get("content", [{}])
        text = content[0].get("text", "") if content else ""
        logger.info("MCP tool=%s elapsed=%dms", name, elapsed)
        return text


# ── Strands-compatible tool wrappers ─────────────────────────
# Strands tools are just Python functions decorated with @tool.
# We generate them dynamically from the MCP tool list.

from strands import tool as strands_tool  # noqa: E402

_mcp_client: MCPLambdaClient | None = None


def get_mcp_client() -> MCPLambdaClient:
    global _mcp_client
    if _mcp_client is None:
        _mcp_client = MCPLambdaClient()
    return _mcp_client


# ── Statically declared Strands tools (best for type safety) ─

@strands_tool
def get_transaction(txn_id: str) -> str:
    """
    Retrieve full details of a transaction including account profile,
    merchant information, location, device fingerprint, and flags.
    Use this first when investigating any transaction.
    """
    return get_mcp_client().call_tool("get_transaction", {"txn_id": txn_id})


@strands_tool
def get_account_history(account_id: str, limit: int = 20) -> str:
    """
    Fetch the last N transactions for an account to identify behavioural
    baselines, spending patterns, and recent anomalies.
    """
    return get_mcp_client().call_tool("get_account_history",
                                      {"account_id": account_id, "limit": limit})


@strands_tool
def get_account_by_txn(txn_id: str) -> str:
    """Get the full account profile of the customer who made this transaction."""
    return get_mcp_client().call_tool("get_account_by_txn", {"txn_id": txn_id})


@strands_tool
def get_risk_signals(txn_id: str) -> str:
    """
    Retrieve all rule-based risk signals already detected for this transaction.
    Signals include severity scores, rule IDs, and descriptions.
    """
    return get_mcp_client().call_tool("get_risk_signals", {"txn_id": txn_id})


@strands_tool
def velocity_check(account_id: str, window_minutes: int = 60) -> str:
    """
    Count how many transactions the account made in the last N minutes.
    Returns txn_count, total_amount, unique_ips, unique_devices.
    Essential for detecting carding, credential stuffing, and burst attacks.
    """
    return get_mcp_client().call_tool("velocity_check",
                                      {"account_id": account_id,
                                       "window_minutes": window_minutes})


@strands_tool
def get_similar_transactions(txn_id: str) -> str:
    """
    Cross-account search: find other accounts' transactions sharing the same
    IP address, device fingerprint, or similar transaction amounts.
    Reveals coordinated fraud rings and shared infrastructure.
    """
    return get_mcp_client().call_tool("get_similar_transactions", {"txn_id": txn_id})


@strands_tool
def get_open_cases(limit: int = 10) -> str:
    """List currently open and escalated fraud cases, ordered by risk score."""
    return get_mcp_client().call_tool("get_open_cases", {"limit": limit})


@strands_tool
def update_case_verdict(case_number: str, verdict: str, reasoning: str,
                        risk_score: int, agent_name: str = "AI-Supervisor") -> str:
    """
    Write the final AI verdict back to the fraud case.
    verdict must be one of: CONFIRMED_FRAUD, LIKELY_FRAUD, SUSPICIOUS,
    LEGITIMATE, NEEDS_REVIEW.
    risk_score is 0-100. This is the final write step — call only once
    all sub-agent analyses are complete.
    """
    return get_mcp_client().call_tool("update_case_verdict", {
        "case_number": case_number, "verdict": verdict,
        "reasoning": reasoning, "risk_score": risk_score,
        "agent_name": agent_name
    })


@strands_tool
def log_agent_action(session_id: str, agent_name: str, action_type: str,
                     input_summary: str = "", output: dict = None,
                     tool_calls: list = None, duration_ms: int = 0) -> str:
    """Append an audit entry to the agent_audit_log table."""
    return get_mcp_client().call_tool("log_agent_action", {
        "session_id": session_id, "agent_name": agent_name,
        "action_type": action_type, "input_summary": input_summary,
        "output": output or {}, "tool_calls": tool_calls or [],
        "duration_ms": duration_ms
    })


# Convenience: all DB tools available for Strands agent construction
DB_TOOLS = [
    get_transaction,
    get_account_history,
    get_account_by_txn,
    get_risk_signals,
    velocity_check,
    get_similar_transactions,
    get_open_cases,
    update_case_verdict,
    log_agent_action,
]
