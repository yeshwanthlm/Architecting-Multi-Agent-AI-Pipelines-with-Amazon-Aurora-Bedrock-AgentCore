"""
SentinelIQ — DB Bootstrap Lambda
Invoked once by Terraform null_resource after Aurora is ready.
Creates schema and inserts seed data.
"""
import json
import logging
import os
import boto3
import psycopg2

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SCHEMA_SQL = """
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

CREATE TABLE IF NOT EXISTS accounts (
    account_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_number VARCHAR(20) UNIQUE NOT NULL,
    customer_name VARCHAR(120) NOT NULL,
    email VARCHAR(200) NOT NULL,
    phone VARCHAR(20),
    account_type VARCHAR(20) NOT NULL CHECK (account_type IN ('personal','business','premium')),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    country_code CHAR(2) NOT NULL DEFAULT 'US',
    risk_tier VARCHAR(10) NOT NULL DEFAULT 'low',
    kyc_verified BOOLEAN NOT NULL DEFAULT TRUE,
    avg_monthly_spend NUMERIC(12,2) DEFAULT 0,
    last_login_at TIMESTAMPTZ,
    last_login_ip INET,
    last_login_device VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS merchants (
    merchant_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_name VARCHAR(200) NOT NULL,
    category VARCHAR(60) NOT NULL,
    mcc_code CHAR(4) NOT NULL,
    country_code CHAR(2) NOT NULL DEFAULT 'US',
    city VARCHAR(100),
    risk_score SMALLINT NOT NULL DEFAULT 10,
    is_blacklisted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS transactions (
    txn_id VARCHAR(30) PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(account_id),
    merchant_id UUID REFERENCES merchants(merchant_id),
    amount NUMERIC(12,2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'USD',
    txn_type VARCHAR(20) NOT NULL,
    channel VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'completed',
    txn_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address INET,
    device_id VARCHAR(100),
    device_type VARCHAR(50),
    latitude NUMERIC(9,6),
    longitude NUMERIC(9,6),
    country_code CHAR(2),
    city VARCHAR(100),
    is_international BOOLEAN NOT NULL DEFAULT FALSE,
    merchant_name VARCHAR(200),
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS risk_signals (
    signal_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    txn_id VARCHAR(30) NOT NULL REFERENCES transactions(txn_id),
    signal_type VARCHAR(60) NOT NULL,
    severity VARCHAR(10) NOT NULL,
    score SMALLINT NOT NULL,
    description TEXT NOT NULL,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    rule_id VARCHAR(40),
    auto_flagged BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS fraud_cases (
    case_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    case_number VARCHAR(20) UNIQUE NOT NULL,
    txn_id VARCHAR(30) REFERENCES transactions(txn_id),
    account_id UUID NOT NULL REFERENCES accounts(account_id),
    fraud_type VARCHAR(60),
    status VARCHAR(20) NOT NULL DEFAULT 'open',
    risk_score SMALLINT,
    analyst_verdict TEXT,
    ai_verdict TEXT,
    ai_reasoning TEXT,
    opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    assigned_to VARCHAR(80)
);

CREATE TABLE IF NOT EXISTS agent_audit_log (
    log_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id VARCHAR(60) NOT NULL,
    agent_name VARCHAR(80) NOT NULL,
    action_type VARCHAR(60) NOT NULL,
    input_summary TEXT,
    output_json JSONB,
    tool_calls JSONB,
    duration_ms INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_txn_account   ON transactions(account_id, txn_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_txn_status    ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_signals_txn   ON risk_signals(txn_id);
CREATE INDEX IF NOT EXISTS idx_cases_status  ON fraud_cases(status);
CREATE INDEX IF NOT EXISTS idx_audit_session ON agent_audit_log(session_id, created_at DESC);
"""


def lambda_handler(event, context):
    logger.info("Bootstrap Lambda invoked")
    try:
        creds = _get_creds()
        conn = psycopg2.connect(
            host=creds["host"], port=creds.get("port", 5432),
            dbname=creds["dbname"], user=creds["username"],
            password=creds["password"], sslmode="require"
        )
        with conn.cursor() as cur:
            logger.info("Creating schema…")
            cur.execute(SCHEMA_SQL)
            logger.info("Loading seed data…")
            _seed(cur)
        conn.commit()
        conn.close()
        logger.info("Bootstrap complete")
        return {"statusCode": 200, "body": json.dumps({"status": "ok"})}
    except Exception as exc:
        logger.exception("Bootstrap failed")
        return {"statusCode": 500, "body": json.dumps({"error": str(exc)})}


def _get_creds():
    client = boto3.client("secretsmanager", region_name=os.environ["REGION"])
    secret = client.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])
    return json.loads(secret["SecretString"])


def _seed(cur):
    # Read seed SQL (embedded inline to keep Lambda self-contained)
    cur.execute("""
    INSERT INTO merchants (merchant_id,merchant_name,category,mcc_code,country_code,city,risk_score,is_blacklisted) VALUES
    ('a1b2c3d4-0001-0001-0001-000000000006','CryptoXchange Pro','Crypto Exchange','6051','US','Online',72,false),
    ('a1b2c3d4-0001-0001-0001-000000000007','LuxuryWatches.ro','Online Jewelry','5944','RO','Bucharest',85,false),
    ('a1b2c3d4-0001-0001-0001-000000000008','FastCash ATM Lagos','ATM/Cash Advance','6011','NG','Lagos',91,true),
    ('a1b2c3d4-0001-0001-0001-000000000009','GiftCard Depot','Gift Cards/Misc','5999','US','Online',68,false),
    ('a1b2c3d4-0001-0001-0001-000000000001','Amazon','Online Retail','5999','US','Seattle',5,false),
    ('a1b2c3d4-0001-0001-0001-000000000002','Starbucks','Restaurant/Cafe','5812','US','New York',3,false),
    ('a1b2c3d4-0001-0001-0001-000000000010','Apple Store','Electronics','5732','US','Cupertino',6,false),
    ('a1b2c3d4-0001-0001-0001-000000000011','Venmo Transfer','P2P Transfer','4829','US','Online',25,false)
    ON CONFLICT DO NOTHING;

    INSERT INTO accounts (account_id,account_number,customer_name,email,phone,account_type,status,country_code,risk_tier,avg_monthly_spend,last_login_ip,last_login_device) VALUES
    ('b1b2c3d4-0001-0001-0001-000000000001','ACC-100001','Sarah Chen','sarah.chen@email.com','+1-415-555-0101','personal','active','US','low',2400.00,'73.162.1.10','iPhone 15 Pro / iOS 17'),
    ('b1b2c3d4-0001-0001-0001-000000000002','ACC-100002','Marcus Williams','mwilliams@company.io','+1-312-555-0202','business','under_review','US','high',15000.00,'185.220.101.47','Unknown Device / Linux'),
    ('b1b2c3d4-0001-0001-0001-000000000003','ACC-100003','Elena Vasquez','elena.v@personal.net','+1-786-555-0303','personal','active','US','medium',1800.00,'181.48.72.11','Samsung Galaxy / Android 14'),
    ('b1b2c3d4-0001-0001-0001-000000000004','ACC-100004','David Okonkwo','d.okonkwo@fintech.com','+44-20-5550404','premium','active','GB','low',42000.00,'86.12.44.201','MacBook Pro / Safari'),
    ('b1b2c3d4-0001-0001-0001-000000000005','ACC-100005','Kevin Zhao','k.zhao.transfers@mail.com','+1-929-555-0505','personal','suspended','US','critical',300.00,'45.33.32.156','Chrome on Windows')
    ON CONFLICT DO NOTHING;

    INSERT INTO transactions (txn_id,account_id,merchant_id,amount,txn_type,channel,status,txn_timestamp,ip_address,device_id,device_type,latitude,longitude,country_code,city,merchant_name,is_international) VALUES
    ('TXN-20240401-8821','b1b2c3d4-0001-0001-0001-000000000001','a1b2c3d4-0001-0001-0001-000000000007',4800.00,'purchase','online','flagged',NOW()-INTERVAL '2 hours','89.34.111.22','dev-unknown-ro-01','Unknown Device',44.4268,26.1025,'RO','Bucharest','LuxuryWatches.ro',true),
    ('TXN-20240401-9001','b1b2c3d4-0001-0001-0001-000000000002','a1b2c3d4-0001-0001-0001-000000000009',500.00,'purchase','online','completed',NOW()-INTERVAL '45 mins','185.220.101.47','dev-unknown-tor','Linux/TorBrowser',NULL,NULL,'US','Unknown','GiftCard Depot',false),
    ('TXN-20240401-9004','b1b2c3d4-0001-0001-0001-000000000002','a1b2c3d4-0001-0001-0001-000000000009',500.00,'purchase','online','flagged',NOW()-INTERVAL '38 mins','185.220.101.47','dev-unknown-tor','Linux/TorBrowser',NULL,NULL,'US','Unknown','GiftCard Depot',false),
    ('TXN-20240401-9005','b1b2c3d4-0001-0001-0001-000000000002','a1b2c3d4-0001-0001-0001-000000000006',2200.00,'purchase','online','flagged',NOW()-INTERVAL '30 mins','185.220.101.47','dev-unknown-tor','Linux/TorBrowser',NULL,NULL,'US','Unknown','CryptoXchange Pro',false),
    ('TXN-20240331-7703','b1b2c3d4-0001-0001-0001-000000000005','a1b2c3d4-0001-0001-0001-000000000008',4700.00,'transfer','online','flagged',NOW()-INTERVAL '3 days','45.33.32.156','dev-kz-chrome','Chrome/Windows',NULL,NULL,'NG','Lagos','FastCash ATM Lagos',true)
    ON CONFLICT DO NOTHING;

    INSERT INTO risk_signals (txn_id,signal_type,severity,score,description,rule_id) VALUES
    ('TXN-20240401-8821','geo_anomaly','critical',95,'Transaction from Romania; account exclusively US-based','RULE-GEO-001'),
    ('TXN-20240401-8821','device_anomaly','high',82,'Unknown device — no match to registered devices','RULE-DEV-002'),
    ('TXN-20240401-8821','amount_outlier','high',78,'$4,800 is 3.7x above 90-day average','RULE-AMT-003'),
    ('TXN-20240401-8821','merchant_risk','high',85,'Merchant has elevated risk score (85/100)','RULE-MERCH-004'),
    ('TXN-20240401-9004','velocity_breach','critical',98,'4 identical gift card purchases within 7 minutes','RULE-VEL-001'),
    ('TXN-20240401-9004','tor_exit_node','critical',99,'IP is a known Tor exit node','RULE-IP-005'),
    ('TXN-20240401-9005','high_risk_merchant','high',80,'Crypto exchange after gift card velocity burst','RULE-CHAIN-006'),
    ('TXN-20240331-7703','structuring','critical',96,'Three transfers just below $5,000 — structuring pattern','RULE-STRUCT-008')
    ON CONFLICT DO NOTHING;

    INSERT INTO fraud_cases (case_number,txn_id,account_id,fraud_type,status,risk_score,assigned_to) VALUES
    ('CASE-2024-0041','TXN-20240401-8821','b1b2c3d4-0001-0001-0001-000000000001','Card-Not-Present Fraud','open',88,'AI-Supervisor'),
    ('CASE-2024-0042','TXN-20240401-9005','b1b2c3d4-0001-0001-0001-000000000002','Account Takeover','investigating',97,'AI-Supervisor'),
    ('CASE-2024-0043','TXN-20240331-7703','b1b2c3d4-0001-0001-0001-000000000005','Money Mule / Structuring','escalated',99,'AI-Supervisor')
    ON CONFLICT DO NOTHING;
    """)
