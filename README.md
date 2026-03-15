# SentinelIQ — Multi-Agent Fraud Detection Platform

> Built with **AWS Strands Agents**, **Amazon Aurora PostgreSQL**, **Amazon Bedrock**, and **MCP (Model Context Protocol)**

```
┌─────────────────────────────────────────────────────────┐
│                    SentinelIQ Platform                    │
│                                                           │
│  User Query ──► Supervisor Agent (Strands)               │
│                      │                                    │
│          ┌───────────┴────────────┐                      │
│          ▼                        ▼                       │
│  Transaction Analyst         Risk Scorer                  │
│  Agent (Strands)             Agent (Strands)              │
│          │                        │                       │
│          ▼                        ▼                       │
│   MCP Server (Lambda)      MCP Server (Lambda)            │
│          │                        │                       │
│          └───────────┬────────────┘                       │
│                      ▼                                    │
│           Amazon Aurora PostgreSQL                        │
│           (Transactions, Accounts,                        │
│            Risk Signals, Audit Log)                       │
└─────────────────────────────────────────────────────────┘
```

## Architecture

| Layer | Technology |
|-------|-----------|
| Agents | AWS Strands SDK (Python) |
| Orchestration | Strands multi-agent supervisor pattern |
| Database | Amazon Aurora PostgreSQL Serverless v2 |
| Tool Protocol | Model Context Protocol (MCP) via Lambda |
| Foundation Model | Claude 3.5 Sonnet on Amazon Bedrock |
| Infrastructure | Terraform |
| UI | FastAPI + Vanilla JS (dark cyberpunk theme) |

## Agents

### 1. Transaction Analyst Agent
- Queries Aurora via MCP tools
- Looks up transaction history, merchant patterns, velocity checks
- Identifies structural anomalies in spending behaviour

### 2. Risk Scorer Agent
- Evaluates signals: geo-anomaly, amount outlier, time-of-day, device fingerprint
- Produces a structured risk score (0–100) with breakdown
- Flags specific risk categories (account takeover, CNP fraud, money mule, etc.)

### 3. Supervisor Agent
- Receives the user's fraud investigation request
- Dispatches sub-agents in parallel using Strands tool-calling
- Synthesizes both outputs into a final verdict + recommended action

## Quick Start

```bash
# 1. Deploy infrastructure
cd terraform
terraform init && terraform apply -auto-approve

# 2. Seed the database
cd ../scripts
python3 bootstrap_handler.py

# 3. Run the agents
cd ../agents
pip install -r requirements.txt
python supervisor.py --txn-id TXN-20240315-8821

# 4. Start the UI
cd ../ui
uvicorn app:app --reload --port 8000
```

## Directory Structure

```
sentineliq/
├── terraform/          # All AWS infrastructure
│   ├── main.tf
│   ├── variables.tf
│   ├── networking.tf
│   ├── aurora.tf
│   ├── lambda.tf
│   ├── iam.tf
│   └── outputs.tf
├── mcp_server/         # Lambda MCP server (DB tools)
│   ├── handler.py
│   ├── tools.py
│   ├── db.py
│   └── requirements.txt
├── agents/             # Strands multi-agent system
│   ├── supervisor.py
│   ├── transaction_analyst.py
│   ├── risk_scorer.py
│   ├── tools.py
│   └── requirements.txt
├── data/               # Seed data & schema
│   ├── schema.sql
│   └── seed.sql
├── scripts/            # Utility scripts
│   └── bootstrap_handler.py
└── ui/                 # FastAPI + JS frontend
    ├── app.py
    ├── static/
    │   └── index.html
    └── requirements.txt
```
