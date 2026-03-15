-- ============================================================
-- SentinelIQ — Seed Data (Realistic Fraud Scenarios)
-- ============================================================

-- ── Merchants ─────────────────────────────────────────────
INSERT INTO merchants (merchant_id, merchant_name, category, mcc_code, country_code, city, risk_score) VALUES
('a1b2c3d4-0001-0001-0001-000000000001', 'Amazon',              'Online Retail',          '5999', 'US', 'Seattle',      5),
('a1b2c3d4-0001-0001-0001-000000000002', 'Starbucks',           'Restaurant/Cafe',        '5812', 'US', 'New York',     3),
('a1b2c3d4-0001-0001-0001-000000000003', 'Shell Gas Station',   'Service Stations',       '5541', 'US', 'Chicago',      8),
('a1b2c3d4-0001-0001-0001-000000000004', 'Delta Airlines',      'Airlines',               '3056', 'US', 'Atlanta',     12),
('a1b2c3d4-0001-0001-0001-000000000005', 'Walmart',             'Discount Stores',        '5310', 'US', 'Bentonville',  4),
('a1b2c3d4-0001-0001-0001-000000000006', 'CryptoXchange Pro',   'Crypto Exchange',        '6051', 'US', 'Online',      72),
('a1b2c3d4-0001-0001-0001-000000000007', 'LuxuryWatches.ro',    'Online Jewelry',         '5944', 'RO', 'Bucharest',   85),
('a1b2c3d4-0001-0001-0001-000000000008', 'FastCash ATM Lagos',  'ATM/Cash Advance',       '6011', 'NG', 'Lagos',       91),
('a1b2c3d4-0001-0001-0001-000000000009', 'GiftCard Depot',      'Gift Cards/Misc',        '5999', 'US', 'Online',      68),
('a1b2c3d4-0001-0001-0001-000000000010', 'Apple Store',         'Electronics',            '5732', 'US', 'Cupertino',    6),
('a1b2c3d4-0001-0001-0001-000000000011', 'Venmo Transfer',      'Peer-to-Peer Transfer',  '4829', 'US', 'Online',      25),
('a1b2c3d4-0001-0001-0001-000000000012', 'QuickLoans247.biz',   'Payday Loans',           '6141', 'US', 'Online',      80)
ON CONFLICT DO NOTHING;

-- ── Accounts ─────────────────────────────────────────────
INSERT INTO accounts (account_id, account_number, customer_name, email, phone, account_type, status, country_code, risk_tier, avg_monthly_spend, last_login_at, last_login_ip, last_login_device) VALUES

-- Normal customer
('b1b2c3d4-0001-0001-0001-000000000001', 'ACC-100001', 'Sarah Chen',      'sarah.chen@email.com',    '+1-415-555-0101', 'personal', 'active',       'US', 'low',      2400.00, NOW() - INTERVAL '2 hours',  '73.162.1.10',    'iPhone 15 Pro / iOS 17'),

-- Account under active attack
('b1b2c3d4-0001-0001-0001-000000000002', 'ACC-100002', 'Marcus Williams', 'mwilliams@company.io',    '+1-312-555-0202', 'business', 'under_review', 'US', 'high',    15000.00, NOW() - INTERVAL '10 mins', '185.220.101.47', 'Unknown Device / Linux'),

-- Compromised personal account
('b1b2c3d4-0001-0001-0001-000000000003', 'ACC-100003', 'Elena Vasquez',   'elena.v@personal.net',    '+1-786-555-0303', 'personal', 'active',       'US', 'medium',   1800.00, NOW() - INTERVAL '1 day',   '181.48.72.11',   'Samsung Galaxy / Android 14'),

-- High-value premium account
('b1b2c3d4-0001-0001-0001-000000000004', 'ACC-100004', 'David Okonkwo',   'd.okonkwo@fintech.com',   '+44-20-5550404', 'premium',  'active',       'GB', 'low',     42000.00, NOW() - INTERVAL '5 hours',  '86.12.44.201',   'MacBook Pro / Safari'),

-- Mule account (recently flagged)
('b1b2c3d4-0001-0001-0001-000000000005', 'ACC-100005', 'Kevin Zhao',      'k.zhao.transfers@mail.com','+1-929-555-0505','personal', 'suspended',    'US', 'critical',  300.00, NOW() - INTERVAL '3 days',  '45.33.32.156',   'Chrome on Windows')

ON CONFLICT DO NOTHING;

-- ── Transactions — Sarah Chen (normal history + 1 anomaly) ─
INSERT INTO transactions (txn_id, account_id, merchant_id, amount, txn_type, channel, status, txn_timestamp, ip_address, device_id, device_type, latitude, longitude, country_code, city, merchant_name, description) VALUES
('TXN-20240301-0001', 'b1b2c3d4-0001-0001-0001-000000000001', 'a1b2c3d4-0001-0001-0001-000000000002', 8.50,   'purchase',  'mobile', 'completed', NOW()-INTERVAL '30 days',  '73.162.1.10', 'dev-iphone-sc-01', 'iPhone 15 Pro', 37.7749, -122.4194, 'US', 'San Francisco', 'Starbucks',           'Morning coffee'),
('TXN-20240305-0002', 'b1b2c3d4-0001-0001-0001-000000000001', 'a1b2c3d4-0001-0001-0001-000000000001', 134.99, 'purchase',  'online', 'completed', NOW()-INTERVAL '26 days',  '73.162.1.10', 'dev-iphone-sc-01', 'iPhone 15 Pro', 37.7749, -122.4194, 'US', 'San Francisco', 'Amazon',              'Books and supplies'),
('TXN-20240310-0003', 'b1b2c3d4-0001-0001-0001-000000000001', 'a1b2c3d4-0001-0001-0001-000000000005', 92.40,  'purchase',  'pos',    'completed', NOW()-INTERVAL '21 days',  '73.162.1.10', 'dev-iphone-sc-01', 'iPhone 15 Pro', 37.7749, -122.4194, 'US', 'San Francisco', 'Walmart',             'Groceries'),
('TXN-20240315-0004', 'b1b2c3d4-0001-0001-0001-000000000001', 'a1b2c3d4-0001-0001-0001-000000000010', 1299.00,'purchase',  'online', 'completed', NOW()-INTERVAL '16 days',  '73.162.1.10', 'dev-iphone-sc-01', 'iPhone 15 Pro', 37.7749, -122.4194, 'US', 'San Francisco', 'Apple Store',         'AirPods Pro'),
-- ANOMALY: Large international transaction from unknown device
('TXN-20240401-8821', 'b1b2c3d4-0001-0001-0001-000000000001', 'a1b2c3d4-0001-0001-0001-000000000007', 4800.00,'purchase',  'online', 'flagged',   NOW()-INTERVAL '2 hours',  '89.34.111.22','dev-unknown-ro-01', 'Unknown Device', 44.4268, 26.1025, 'RO', 'Bucharest',     'LuxuryWatches.ro',    'Luxury watch purchase - Romania', TRUE)
ON CONFLICT DO NOTHING;

-- ── Transactions — Marcus Williams (velocity fraud) ───────
INSERT INTO transactions (txn_id, account_id, merchant_id, amount, txn_type, channel, status, txn_timestamp, ip_address, device_id, device_type, latitude, longitude, country_code, city, merchant_name, is_international) VALUES
('TXN-20240401-9001', 'b1b2c3d4-0001-0001-0001-000000000002', 'a1b2c3d4-0001-0001-0001-000000000009', 500.00,  'purchase', 'online', 'completed', NOW()-INTERVAL '45 mins', '185.220.101.47', 'dev-unknown-tor', 'Linux/TorBrowser', 0, 0, 'US', 'Unknown', 'GiftCard Depot', FALSE),
('TXN-20240401-9002', 'b1b2c3d4-0001-0001-0001-000000000002', 'a1b2c3d4-0001-0001-0001-000000000009', 500.00,  'purchase', 'online', 'completed', NOW()-INTERVAL '43 mins', '185.220.101.47', 'dev-unknown-tor', 'Linux/TorBrowser', 0, 0, 'US', 'Unknown', 'GiftCard Depot', FALSE),
('TXN-20240401-9003', 'b1b2c3d4-0001-0001-0001-000000000002', 'a1b2c3d4-0001-0001-0001-000000000009', 500.00,  'purchase', 'online', 'completed', NOW()-INTERVAL '41 mins', '185.220.101.47', 'dev-unknown-tor', 'Linux/TorBrowser', 0, 0, 'US', 'Unknown', 'GiftCard Depot', FALSE),
('TXN-20240401-9004', 'b1b2c3d4-0001-0001-0001-000000000002', 'a1b2c3d4-0001-0001-0001-000000000009', 500.00,  'purchase', 'online', 'flagged',   NOW()-INTERVAL '38 mins', '185.220.101.47', 'dev-unknown-tor', 'Linux/TorBrowser', 0, 0, 'US', 'Unknown', 'GiftCard Depot', FALSE),
('TXN-20240401-9005', 'b1b2c3d4-0001-0001-0001-000000000002', 'a1b2c3d4-0001-0001-0001-000000000006', 2200.00, 'purchase', 'online', 'flagged',   NOW()-INTERVAL '30 mins', '185.220.101.47', 'dev-unknown-tor', 'Linux/TorBrowser', 0, 0, 'US', 'Unknown', 'CryptoXchange Pro', FALSE)
ON CONFLICT DO NOTHING;

-- ── Transactions — Kevin Zhao (money mule pattern) ────────
INSERT INTO transactions (txn_id, account_id, merchant_id, amount, txn_type, channel, status, txn_timestamp, ip_address, device_id, device_type, country_code, city, merchant_name) VALUES
('TXN-20240329-7701', 'b1b2c3d4-0001-0001-0001-000000000005', 'a1b2c3d4-0001-0001-0001-000000000011', 4900.00, 'transfer', 'online', 'completed', NOW()-INTERVAL '5 days', '45.33.32.156', 'dev-kz-chrome', 'Chrome/Windows', 'US', 'New York',   'Venmo Transfer'),
('TXN-20240330-7702', 'b1b2c3d4-0001-0001-0001-000000000005', 'a1b2c3d4-0001-0001-0001-000000000011', 4800.00, 'transfer', 'online', 'completed', NOW()-INTERVAL '4 days', '45.33.32.156', 'dev-kz-chrome', 'Chrome/Windows', 'US', 'New York',   'Venmo Transfer'),
('TXN-20240331-7703', 'b1b2c3d4-0001-0001-0001-000000000005', 'a1b2c3d4-0001-0001-0001-000000000008', 4700.00, 'transfer', 'online', 'flagged',   NOW()-INTERVAL '3 days', '45.33.32.156', 'dev-kz-chrome', 'Chrome/Windows', 'NG', 'Lagos',      'FastCash ATM Lagos')
ON CONFLICT DO NOTHING;

-- ── Risk Signals ──────────────────────────────────────────
INSERT INTO risk_signals (txn_id, signal_type, severity, score, description, rule_id) VALUES
-- Sarah's anomaly
('TXN-20240401-8821', 'geo_anomaly',        'critical', 95, 'Transaction originated in Romania; account holder''s last 90 days are exclusively US-based',    'RULE-GEO-001'),
('TXN-20240401-8821', 'device_anomaly',     'high',     82, 'Unknown device fingerprint — no match to any registered device on this account',                 'RULE-DEV-002'),
('TXN-20240401-8821', 'amount_outlier',     'high',     78, 'Transaction amount $4,800 is 3.7x above account''s 90-day average ($1,299)',                     'RULE-AMT-003'),
('TXN-20240401-8821', 'merchant_risk',      'high',     85, 'Merchant LuxuryWatches.ro has elevated risk score (85/100) and is registered in high-risk jurisdiction', 'RULE-MERCH-004'),

-- Marcus velocity
('TXN-20240401-9004', 'velocity_breach',    'critical', 98, '4 identical gift-card purchases within 7 minutes from same IP — classic cashing-out pattern',   'RULE-VEL-001'),
('TXN-20240401-9004', 'tor_exit_node',      'critical', 99, 'IP 185.220.101.47 is a known Tor exit node listed in threat intelligence feeds',                 'RULE-IP-005'),
('TXN-20240401-9005', 'high_risk_merchant', 'high',     80, 'Crypto exchange transaction immediately following gift card velocity burst — money movement chain', 'RULE-CHAIN-006'),

-- Kevin mule
('TXN-20240331-7703', 'international_wire', 'critical', 97, 'Funds routed to high-risk Nigerian entity following structured US transfers just below $5,000',   'RULE-MULE-007'),
('TXN-20240331-7703', 'structuring',        'critical', 96, 'Three consecutive transfers of $4,900 / $4,800 / $4,700 — consistent structuring to avoid CTR',   'RULE-STRUCT-008')
ON CONFLICT DO NOTHING;

-- ── Fraud Cases ───────────────────────────────────────────
INSERT INTO fraud_cases (case_number, txn_id, account_id, fraud_type, status, risk_score, opened_at, assigned_to) VALUES
('CASE-2024-0041', 'TXN-20240401-8821', 'b1b2c3d4-0001-0001-0001-000000000001', 'Card-Not-Present Fraud',  'open',          88, NOW()-INTERVAL '2 hours',  'AI-Supervisor'),
('CASE-2024-0042', 'TXN-20240401-9004', 'b1b2c3d4-0001-0001-0001-000000000002', 'Account Takeover',        'investigating', 97, NOW()-INTERVAL '30 mins',  'AI-Supervisor'),
('CASE-2024-0043', 'TXN-20240331-7703', 'b1b2c3d4-0001-0001-0001-000000000005', 'Money Mule / Structuring','escalated',     99, NOW()-INTERVAL '3 days',   'AI-Supervisor')
ON CONFLICT DO NOTHING;
