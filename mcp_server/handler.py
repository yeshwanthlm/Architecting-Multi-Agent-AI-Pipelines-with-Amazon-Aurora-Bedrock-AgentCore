"""
SentinelIQ MCP Server — Lambda Handler
Implements the Model Context Protocol (MCP) so Strands agents can
call typed DB tools over a standard interface.
"""
import json
import logging
import os
from tools import TOOL_REGISTRY, execute_tool

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))


def lambda_handler(event: dict, context) -> dict:
    """
    MCP-over-Lambda dispatcher.

    Strands sends a JSON body shaped like:
        {"method": "tools/call", "params": {"name": "...", "arguments": {...}}}
    or for discovery:
        {"method": "tools/list"}

    Returns the MCP-spec response envelope.
    """
    try:
        body = event if isinstance(event, dict) else json.loads(event.get("body", "{}"))
        method = body.get("method", "")

        # ── Discovery: list all available tools ──────────────
        if method == "tools/list":
            return _ok({"tools": [t["spec"] for t in TOOL_REGISTRY.values()]})

        # ── Invocation ────────────────────────────────────────
        if method == "tools/call":
            params = body.get("params", {})
            tool_name = params.get("name")
            arguments = params.get("arguments", {})

            if tool_name not in TOOL_REGISTRY:
                return _error(f"Unknown tool: {tool_name}", code=-32601)

            logger.info("Invoking tool=%s args=%s", tool_name, json.dumps(arguments))
            result = execute_tool(tool_name, arguments)
            return _ok({"content": [{"type": "text", "text": json.dumps(result, default=str)}]})

        return _error(f"Unsupported method: {method}", code=-32600)

    except Exception as exc:
        logger.exception("Unhandled error in MCP handler")
        return _error(str(exc), code=-32603)


def _ok(data: dict) -> dict:
    return {"statusCode": 200, "body": json.dumps({"jsonrpc": "2.0", "id": 1, "result": data}),
            "headers": {"Content-Type": "application/json"}}


def _error(message: str, code: int = -32603) -> dict:
    return {"statusCode": 200,  # MCP errors are protocol-level, not HTTP-level
            "body": json.dumps({"jsonrpc": "2.0", "id": 1,
                                "error": {"code": code, "message": message}}),
            "headers": {"Content-Type": "application/json"}}
