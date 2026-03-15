-- ============================================================
-- SentinelIQ — Fraud Detection Database Schema
-- Aurora PostgreSQL 15
-- ============================================================

-- ── Extensions ───────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- fuzzy text search

-- ── accounts ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS accounts (
    account_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_number    VARCHAR(20)  UNIQUE NOT NULL,
    customer_name     VARCHAR(120) NOT NULL,
    email             VARCHAR(200) NOT NULL,
    phone             VARCHAR(20),
    account_type      VARCHAR(20)  NOT NULL CHECK (account_type IN ('personal','business','premium')),
    status            VARCHAR(20)  NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','closed','under_review')),
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    country_code      CHAR(2)      NOT NULL DEFAULT 'US',
    risk_tier         VARCHAR(10)  NOT NULL DEFAULT 'low' CHECK (risk_tier IN ('low','medium','high','critical')),
    kyc_verified      BOOLEAN      NOT NULL DEFAULT TRUE,
    avg_monthly_spend NUMERIC(12,2) DEFAULT 0,
    last_login_at     TIMESTAMPTZ,
    last_login_ip     INET,
    last_login_device VARCHAR(200)
);

-- ── merchants ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS merchants (
    merchant_id    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_name  VARCHAR(200) NOT NULL,
    category       VARCHAR(60)  NOT NULL,  -- MCC category description
    mcc_code       CHAR(4)      NOT NULL,
    country_code   CHAR(2)      NOT NULL DEFAULT 'US',
    city           VARCHAR(100),
    risk_score     SMALLINT     NOT NULL DEFAULT 10 CHECK (risk_score BETWEEN 0 AND 100),
    is_blacklisted BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── transactions ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS transactions (
    txn_id           VARCHAR(30)  PRIMARY KEY,
    account_id       UUID         NOT NULL REFERENCES accounts(account_id),
    merchant_id      UUID         REFERENCES merchants(merchant_id),
    amount           NUMERIC(12,2) NOT NULL,
    currency         CHAR(3)      NOT NULL DEFAULT 'USD',
    txn_type         VARCHAR(20)  NOT NULL CHECK (txn_type IN ('purchase','withdrawal','transfer','refund','chargeback')),
    channel          VARCHAR(20)  NOT NULL CHECK (channel IN ('online','pos','atm','mobile','wire')),
    status           VARCHAR(20)  NOT NULL DEFAULT 'completed' CHECK (status IN ('pending','completed','failed','flagged','reversed')),
    txn_timestamp    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    ip_address       INET,
    device_id        VARCHAR(100),
    device_type      VARCHAR(50),
    latitude         NUMERIC(9,6),
    longitude        NUMERIC(9,6),
    country_code     CHAR(2),
    city             VARCHAR(100),
    is_international BOOLEAN      NOT NULL DEFAULT FALSE,
    merchant_name    VARCHAR(200),
    description      TEXT,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── risk_signals ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS risk_signals (
    signal_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    txn_id          VARCHAR(30)  NOT NULL REFERENCES transactions(txn_id),
    signal_type     VARCHAR(60)  NOT NULL,
    severity        VARCHAR(10)  NOT NULL CHECK (severity IN ('low','medium','high','critical')),
    score           SMALLINT     NOT NULL CHECK (score BETWEEN 0 AND 100),
    description     TEXT         NOT NULL,
    detected_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    rule_id         VARCHAR(40),
    auto_flagged    BOOLEAN      NOT NULL DEFAULT TRUE
);

-- ── fraud_cases ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS fraud_cases (
    case_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    case_number      VARCHAR(20)  UNIQUE NOT NULL,
    txn_id           VARCHAR(30)  REFERENCES transactions(txn_id),
    account_id       UUID         NOT NULL REFERENCES accounts(account_id),
    fraud_type       VARCHAR(60),
    status           VARCHAR(20)  NOT NULL DEFAULT 'open' CHECK (status IN ('open','investigating','confirmed','dismissed','escalated')),
    risk_score       SMALLINT     CHECK (risk_score BETWEEN 0 AND 100),
    analyst_verdict  TEXT,
    ai_verdict       TEXT,
    ai_reasoning     TEXT,
    opened_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    resolved_at      TIMESTAMPTZ,
    assigned_to      VARCHAR(80)
);

-- ── agent_audit_log ───────────────────────────────────────
-- Every agent invocation is logged here for explainability
CREATE TABLE IF NOT EXISTS agent_audit_log (
    log_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id    VARCHAR(60)  NOT NULL,
    agent_name    VARCHAR(80)  NOT NULL,
    action_type   VARCHAR(60)  NOT NULL,
    input_summary TEXT,
    output_json   JSONB,
    tool_calls    JSONB,
    duration_ms   INTEGER,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── Indexes ───────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_txn_account      ON transactions(account_id, txn_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_txn_timestamp    ON transactions(txn_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_txn_status       ON transactions(status) WHERE status IN ('flagged','pending');
CREATE INDEX IF NOT EXISTS idx_txn_amount       ON transactions(amount DESC);
CREATE INDEX IF NOT EXISTS idx_txn_device       ON transactions(device_id);
CREATE INDEX IF NOT EXISTS idx_txn_ip           ON transactions(ip_address);
CREATE INDEX IF NOT EXISTS idx_signals_txn      ON risk_signals(txn_id);
CREATE INDEX IF NOT EXISTS idx_signals_type     ON risk_signals(signal_type, severity);
CREATE INDEX IF NOT EXISTS idx_cases_account    ON fraud_cases(account_id);
CREATE INDEX IF NOT EXISTS idx_cases_status     ON fraud_cases(status);
CREATE INDEX IF NOT EXISTS idx_audit_session    ON agent_audit_log(session_id, created_at DESC);
