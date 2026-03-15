"""
SentinelIQ MCP Server — Tool Registry
Each entry defines:
  - spec:    the MCP tool spec (name, description, inputSchema)
  - handler: Python function that executes the tool
"""
from __future__ import annotations
import logging
from db import query

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────
# Tool implementations
# ─────────────────────────────────────────────────────────────

def get_transaction(txn_id: str) -> dict:
    """Fetch a single transaction with merchant and account details."""
    row = query("""
        SELECT
            t.txn_id, t.amount, t.currency, t.txn_type, t.channel, t.status,
            t.txn_timestamp, t.ip_address::text, t.device_id, t.device_type,
            t.latitude, t.longitude, t.country_code, t.city,
            t.is_international, t.merchant_name, t.description,
            a.account_number, a.customer_name, a.email, a.account_type,
            a.status AS account_status, a.risk_tier, a.avg_monthly_spend,
            a.last_login_at, a.last_login_ip::text, a.last_login_device,
            m.merchant_name AS merchant_full_name, m.category AS merchant_category,
            m.mcc_code, m.risk_score AS merchant_risk_score, m.is_blacklisted,
            m.country_code AS merchant_country
        FROM transactions t
        JOIN accounts a ON a.account_id = t.account_id
        LEFT JOIN merchants m ON m.merchant_id = t.merchant_id
        WHERE t.txn_id = %s
    """, (txn_id,), fetch="one")
    if not row:
        return {"error": f"Transaction {txn_id!r} not found"}
    return row


def get_account_history(account_id: str, limit: int = 20) -> list[dict]:
    """Fetch recent transaction history for an account."""
    return query("""
        SELECT txn_id, amount, currency, txn_type, channel, status,
               txn_timestamp, country_code, city, merchant_name,
               device_id, ip_address::text, is_international
        FROM transactions
        WHERE account_id = %s
        ORDER BY txn_timestamp DESC
        LIMIT %s
    """, (account_id, min(limit, 50)))


def get_account_by_txn(txn_id: str) -> dict:
    """Get full account profile for the account that made this transaction."""
    row = query("""
        SELECT a.account_id::text, a.account_number, a.customer_name, a.email,
               a.account_type, a.status, a.country_code, a.risk_tier,
               a.kyc_verified, a.avg_monthly_spend, a.created_at,
               a.last_login_at, a.last_login_ip::text, a.last_login_device
        FROM accounts a
        JOIN transactions t ON t.account_id = a.account_id
        WHERE t.txn_id = %s
    """, (txn_id,), fetch="one")
    return row or {"error": f"No account found for txn {txn_id!r}"}


def get_risk_signals(txn_id: str) -> list[dict]:
    """Fetch all risk signals fired against a transaction."""
    return query("""
        SELECT signal_type, severity, score, description, rule_id, detected_at
        FROM risk_signals
        WHERE txn_id = %s
        ORDER BY score DESC
    """, (txn_id,))


def velocity_check(account_id: str, window_minutes: int = 60) -> dict:
    """Count transactions in a rolling time window — detects velocity attacks."""
    row = query("""
        SELECT
            COUNT(*) AS txn_count,
            SUM(amount) AS total_amount,
            COUNT(DISTINCT ip_address::text) AS unique_ips,
            COUNT(DISTINCT device_id) AS unique_devices,
            MAX(amount) AS max_amount,
            MIN(txn_timestamp) AS window_start,
            MAX(txn_timestamp) AS window_end
        FROM transactions
        WHERE account_id = %s
          AND txn_timestamp >= NOW() - (%s || ' minutes')::INTERVAL
          AND status NOT IN ('failed', 'reversed')
    """, (account_id, str(window_minutes)), fetch="one")
    return row or {}


def get_similar_transactions(txn_id: str) -> list[dict]:
    """Find other transactions with similar IP, device, or amount patterns."""
    return query("""
        WITH target AS (
            SELECT ip_address, device_id, amount * 0.8 AS amt_low,
                   amount * 1.2 AS amt_high, account_id
            FROM transactions WHERE txn_id = %s
        )
        SELECT t.txn_id, t.account_id::text, t.amount, t.status,
               t.txn_timestamp, t.ip_address::text, t.device_id,
               t.merchant_name, t.country_code,
               CASE
                 WHEN t.ip_address = tgt.ip_address THEN 'same_ip'
                 WHEN t.device_id = tgt.device_id   THEN 'same_device'
                 ELSE 'similar_amount'
               END AS match_reason
        FROM transactions t, target tgt
        WHERE t.txn_id != %s
          AND t.account_id != tgt.account_id
          AND (
            t.ip_address = tgt.ip_address
            OR t.device_id = tgt.device_id
            OR t.amount BETWEEN tgt.amt_low AND tgt.amt_high
          )
        ORDER BY t.txn_timestamp DESC
        LIMIT 10
    """, (txn_id, txn_id))


def get_open_cases(limit: int = 10) -> list[dict]:
    """List open fraud cases ordered by risk score."""
    return query("""
        SELECT fc.case_number, fc.fraud_type, fc.status, fc.risk_score,
               fc.opened_at, fc.assigned_to,
               a.customer_name, a.account_number, a.risk_tier,
               t.amount, t.currency, t.txn_id
        FROM fraud_cases fc
        JOIN accounts a ON a.account_id = fc.account_id
        LEFT JOIN transactions t ON t.txn_id = fc.txn_id
        WHERE fc.status IN ('open', 'investigating', 'escalated')
        ORDER BY fc.risk_score DESC NULLS LAST, fc.opened_at ASC
        LIMIT %s
    """, (min(limit, 50),))


def update_case_verdict(case_number: str, verdict: str, reasoning: str,
                        risk_score: int, agent_name: str = "AI-Supervisor") -> dict:
    """Write AI verdict back to the fraud case."""
    query("""
        UPDATE fraud_cases
        SET ai_verdict   = %s,
            ai_reasoning = %s,
            risk_score   = %s,
            status       = CASE WHEN %s >= 80 THEN 'escalated'
                                WHEN %s >= 50 THEN 'investigating'
                                ELSE 'open' END,
            assigned_to  = %s
        WHERE case_number = %s
    """, (verdict, reasoning, risk_score, risk_score, risk_score, agent_name, case_number),
    fetch="none")
    return {"updated": case_number, "new_risk_score": risk_score, "verdict": verdict}


def log_agent_action(session_id: str, agent_name: str, action_type: str,
                     input_summary: str, output: dict, tool_calls: list,
                     duration_ms: int) -> dict:
    """Append an entry to the agent audit log."""
    import json
    query("""
        INSERT INTO agent_audit_log
            (session_id, agent_name, action_type, input_summary,
             output_json, tool_calls, duration_ms)
        VALUES (%s, %s, %s, %s, %s::jsonb, %s::jsonb, %s)
    """, (session_id, agent_name, action_type, input_summary,
          json.dumps(output, default=str),
          json.dumps(tool_calls, default=str),
          duration_ms), fetch="none")
    return {"logged": True}


# ─────────────────────────────────────────────────────────────
# Tool Registry — the single source of truth
# ─────────────────────────────────────────────────────────────

TOOL_REGISTRY: dict[str, dict] = {

    "get_transaction": {
        "spec": {
            "name": "get_transaction",
            "description": "Retrieve full details of a transaction including account and merchant information.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "txn_id": {"type": "string", "description": "Transaction ID (e.g. TXN-20240401-8821)"}
                },
                "required": ["txn_id"]
            }
        },
        "fn": lambda args: get_transaction(args["txn_id"])
    },

    "get_account_history": {
        "spec": {
            "name": "get_account_history",
            "description": "Fetch recent transaction history for an account to spot behavioural patterns.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "account_id": {"type": "string"},
                    "limit": {"type": "integer", "default": 20, "maximum": 50}
                },
                "required": ["account_id"]
            }
        },
        "fn": lambda args: get_account_history(args["account_id"], args.get("limit", 20))
    },

    "get_account_by_txn": {
        "spec": {
            "name": "get_account_by_txn",
            "description": "Get the full account profile of whoever made a given transaction.",
            "inputSchema": {
                "type": "object",
                "properties": {"txn_id": {"type": "string"}},
                "required": ["txn_id"]
            }
        },
        "fn": lambda args: get_account_by_txn(args["txn_id"])
    },

    "get_risk_signals": {
        "spec": {
            "name": "get_risk_signals",
            "description": "Retrieve all risk signals and rule violations fired against a transaction.",
            "inputSchema": {
                "type": "object",
                "properties": {"txn_id": {"type": "string"}},
                "required": ["txn_id"]
            }
        },
        "fn": lambda args: get_risk_signals(args["txn_id"])
    },

    "velocity_check": {
        "spec": {
            "name": "velocity_check",
            "description": "Count how many transactions an account made in a rolling time window. Detects velocity fraud and burst patterns.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "account_id": {"type": "string"},
                    "window_minutes": {"type": "integer", "default": 60, "description": "Rolling window in minutes"}
                },
                "required": ["account_id"]
            }
        },
        "fn": lambda args: velocity_check(args["account_id"], args.get("window_minutes", 60))
    },

    "get_similar_transactions": {
        "spec": {
            "name": "get_similar_transactions",
            "description": "Find transactions from OTHER accounts sharing the same IP, device, or similar amount — reveals fraud rings.",
            "inputSchema": {
                "type": "object",
                "properties": {"txn_id": {"type": "string"}},
                "required": ["txn_id"]
            }
        },
        "fn": lambda args: get_similar_transactions(args["txn_id"])
    },

    "get_open_cases": {
        "spec": {
            "name": "get_open_cases",
            "description": "List open and escalated fraud cases ordered by risk score.",
            "inputSchema": {
                "type": "object",
                "properties": {"limit": {"type": "integer", "default": 10}},
                "required": []
            }
        },
        "fn": lambda args: get_open_cases(args.get("limit", 10))
    },

    "update_case_verdict": {
        "spec": {
            "name": "update_case_verdict",
            "description": "Write the AI verdict and risk score back to a fraud case in the database.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "case_number": {"type": "string"},
                    "verdict": {"type": "string", "enum": ["CONFIRMED_FRAUD", "LIKELY_FRAUD", "SUSPICIOUS", "LEGITIMATE", "NEEDS_REVIEW"]},
                    "reasoning": {"type": "string"},
                    "risk_score": {"type": "integer", "minimum": 0, "maximum": 100},
                    "agent_name": {"type": "string"}
                },
                "required": ["case_number", "verdict", "reasoning", "risk_score"]
            }
        },
        "fn": lambda args: update_case_verdict(
            args["case_number"], args["verdict"], args["reasoning"],
            args["risk_score"], args.get("agent_name", "AI-Supervisor"))
    },

    "log_agent_action": {
        "spec": {
            "name": "log_agent_action",
            "description": "Append an entry to the agent audit trail for explainability and compliance.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                    "agent_name": {"type": "string"},
                    "action_type": {"type": "string"},
                    "input_summary": {"type": "string"},
                    "output": {"type": "object"},
                    "tool_calls": {"type": "array"},
                    "duration_ms": {"type": "integer"}
                },
                "required": ["session_id", "agent_name", "action_type"]
            }
        },
        "fn": lambda args: log_agent_action(
            args["session_id"], args["agent_name"], args["action_type"],
            args.get("input_summary", ""), args.get("output", {}),
            args.get("tool_calls", []), args.get("duration_ms", 0))
    }
}


def execute_tool(name: str, arguments: dict):
    """Dispatch to the correct tool handler."""
    return TOOL_REGISTRY[name]["fn"](arguments)
