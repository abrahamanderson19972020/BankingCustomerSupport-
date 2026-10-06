-- Banking Customer Support Agent - Supabase Schema
-- This schema is optimized for PCI-DSS and GDPR compliance

-- ============================================
-- 1. CUSTOMERS TABLE
-- ============================================
CREATE TABLE customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username VARCHAR(50) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  phone_hash VARCHAR(255) NOT NULL, -- Never store actual phone
  password_hash VARCHAR(255) NOT NULL,
  
  -- Personal info (masked)
  first_name VARCHAR(100) NOT NULL,
  last_name VARCHAR(100) NOT NULL,
  date_of_birth DATE NOT NULL,
  
  -- KYC (Know Your Customer)
  kyc_verified BOOLEAN DEFAULT false,
  kyc_verified_at TIMESTAMP,
  
  -- Risk scoring
  risk_score INTEGER DEFAULT 0, -- 0-100 (0 = low risk, 100 = high risk)
  is_active BOOLEAN DEFAULT true,
  
  -- Compliance flags
  on_sanctions_list BOOLEAN DEFAULT false,
  aml_flag BOOLEAN DEFAULT false,
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now(),
  last_login TIMESTAMP
);

CREATE INDEX idx_customers_email ON customers(email);
CREATE INDEX idx_customers_username ON customers(username);
CREATE INDEX idx_customers_risk_score ON customers(risk_score);

-- ============================================
-- 2. ACCOUNTS TABLE (Multiple per customer)
-- ============================================
CREATE TABLE accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  
  account_number VARCHAR(20) UNIQUE NOT NULL,
  account_type VARCHAR(50) NOT NULL, -- 'savings', 'checking', 'investment'
  currency VARCHAR(3) DEFAULT 'EUR', -- ISO 4217
  
  -- Balance (in cents to avoid floating point)
  balance_cents BIGINT DEFAULT 0,
  
  -- Account status
  status VARCHAR(20) DEFAULT 'active', -- 'active', 'frozen', 'closed', 'suspended'
  status_reason TEXT,
  
  -- Limits
  daily_transfer_limit_cents BIGINT DEFAULT 1000000, -- €10,000
  monthly_transfer_limit_cents BIGINT DEFAULT 10000000, -- €100,000
  
  -- Fraud detection
  card_blocked BOOLEAN DEFAULT false,
  card_block_reason TEXT,
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

CREATE INDEX idx_accounts_customer_id ON accounts(customer_id);
CREATE INDEX idx_accounts_account_number ON accounts(account_number);
CREATE INDEX idx_accounts_status ON accounts(status);

-- ============================================
-- 3. CARDS TABLE (Debit/Credit cards)
-- ============================================
CREATE TABLE cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  
  -- Card details (masked)
  card_last_four VARCHAR(4) NOT NULL,
  card_type VARCHAR(20) NOT NULL, -- 'debit', 'credit'
  card_network VARCHAR(20) NOT NULL, -- 'visa', 'mastercard'
  
  -- Sensitive data hash
  card_hash VARCHAR(255) NOT NULL, -- SHA-256 hash of full card number
  
  -- Status
  status VARCHAR(20) DEFAULT 'active', -- 'active', 'blocked', 'expired', 'cancelled'
  is_blocked BOOLEAN DEFAULT false,
  block_reason TEXT,
  
  -- Dates
  issued_date DATE NOT NULL,
  expiry_date DATE NOT NULL,
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

CREATE INDEX idx_cards_account_id ON cards(account_id);
CREATE INDEX idx_cards_customer_id ON cards(customer_id);
CREATE INDEX idx_cards_status ON cards(status);

-- ============================================
-- 4. TRANSACTIONS TABLE (All movements)
-- ============================================
CREATE TABLE transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id),
  customer_id UUID NOT NULL REFERENCES customers(id),
  
  transaction_type VARCHAR(50) NOT NULL, -- 'transfer', 'payment', 'withdrawal', 'deposit'
  amount_cents BIGINT NOT NULL,
  currency VARCHAR(3) DEFAULT 'EUR',
  
  -- Transaction details
  description TEXT,
  reference_number VARCHAR(50) UNIQUE,
  
  -- Counterparty
  counterparty_account VARCHAR(50),
  counterparty_name VARCHAR(200),
  counterparty_iban VARCHAR(34),
  
  -- Status
  status VARCHAR(20) DEFAULT 'completed', -- 'pending', 'completed', 'failed', 'reversed'
  
  -- Fraud scoring
  fraud_score INTEGER DEFAULT 0, -- 0-100
  flagged_for_review BOOLEAN DEFAULT false,
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT now(),
  completed_at TIMESTAMP,
  updated_at TIMESTAMP DEFAULT now()
);

CREATE INDEX idx_transactions_account_id ON transactions(account_id);
CREATE INDEX idx_transactions_customer_id ON transactions(customer_id);
CREATE INDEX idx_transactions_created_at ON transactions(created_at);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_fraud_score ON transactions(fraud_score);

-- ============================================
-- 5. CUSTOMER SESSIONS (For agent interactions)
-- ============================================
CREATE TABLE customer_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  
  session_token VARCHAR(255) UNIQUE NOT NULL,
  
  -- 2FA verification
  twofa_verified BOOLEAN DEFAULT false,
  twofa_verified_at TIMESTAMP,
  twofa_attempts INTEGER DEFAULT 0,
  
  -- Session status
  is_active BOOLEAN DEFAULT true,
  ip_address INET,
  device_info TEXT, -- User-Agent
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT now(),
  expires_at TIMESTAMP,
  last_activity TIMESTAMP DEFAULT now()
);

CREATE INDEX idx_sessions_customer_id ON customer_sessions(customer_id);
CREATE INDEX idx_sessions_token ON customer_sessions(session_token);
CREATE INDEX idx_sessions_expires_at ON customer_sessions(expires_at);

-- ============================================
-- 6. SUPPORT INTERACTIONS (Agent conversations)
-- ============================================
CREATE TABLE support_interactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  session_id UUID REFERENCES customer_sessions(id),
  
  -- Channel
  channel VARCHAR(50) NOT NULL, -- 'chat', 'phone', 'email'
  
  -- Interaction metadata
  intent VARCHAR(100), -- Detected intent
  sentiment VARCHAR(20), -- 'positive', 'negative', 'neutral'
  
  -- Status
  status VARCHAR(20) DEFAULT 'open', -- 'open', 'resolved', 'escalated', 'closed'
  requires_human_review BOOLEAN DEFAULT false,
  
  -- Agent assignment
  assigned_agent_id UUID,
  assigned_at TIMESTAMP,
  
  -- Timestamps
  started_at TIMESTAMP DEFAULT now(),
  resolved_at TIMESTAMP,
  updated_at TIMESTAMP DEFAULT now()
);

CREATE INDEX idx_interactions_customer_id ON support_interactions(customer_id);
CREATE INDEX idx_interactions_status ON support_interactions(status);
CREATE INDEX idx_interactions_channel ON support_interactions(channel);
CREATE INDEX idx_interactions_requires_review ON support_interactions(requires_human_review);

-- ============================================
-- 7. INTERACTION MESSAGES (Chat history)
-- ============================================
CREATE TABLE interaction_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  interaction_id UUID NOT NULL REFERENCES support_interactions(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES customers(id),
  
  -- Message details
  sender_type VARCHAR(20) NOT NULL, -- 'customer', 'agent', 'system'
  message_text TEXT NOT NULL,
  
  -- Sentiment & intent
  sentiment VARCHAR(20),
  detected_intent VARCHAR(100),
  
  -- Compliance
  contains_pii BOOLEAN DEFAULT false, -- Does message contain personal info?
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT now()
);

CREATE INDEX idx_messages_interaction_id ON interaction_messages(interaction_id);
CREATE INDEX idx_messages_customer_id ON interaction_messages(customer_id);
CREATE INDEX idx_messages_sender_type ON interaction_messages(sender_type);

-- ============================================
-- 8. AUDIT LOG (Compliance requirement)
-- ============================================
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Who & What
  customer_id UUID REFERENCES customers(id),
  action_type VARCHAR(100) NOT NULL,
  resource_type VARCHAR(50), -- 'account', 'card', 'transaction'
  resource_id UUID,
  
  -- Action details
  action_description TEXT,
  old_values JSONB, -- Previous state
  new_values JSONB, -- New state
  
  -- Compliance
  ip_address INET,
  user_agent TEXT,
  
  -- Timestamps (immutable)
  created_at TIMESTAMP DEFAULT now()
);

CREATE INDEX idx_audit_customer_id ON audit_logs(customer_id);
CREATE INDEX idx_audit_action_type ON audit_logs(action_type);
CREATE INDEX idx_audit_resource_type ON audit_logs(resource_type);
CREATE INDEX idx_audit_created_at ON audit_logs(created_at);

-- ============================================
-- 9. FRAUD ALERTS (Real-time detection)
-- ============================================
CREATE TABLE fraud_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  
  -- Alert details
  alert_type VARCHAR(50) NOT NULL, -- 'suspicious_location', 'velocity_check', 'amount_anomaly'
  severity VARCHAR(20) NOT NULL, -- 'low', 'medium', 'high', 'critical'
  
  -- Detection details
  description TEXT,
  confidence_score DECIMAL(3,2), -- 0.00 to 1.00
  
  -- Transaction reference
  transaction_id UUID REFERENCES transactions(id),
  
  -- Status
  status VARCHAR(20) DEFAULT 'open', -- 'open', 'reviewed', 'resolved', 'false_alarm'
  reviewed_by UUID, -- Agent ID
  reviewed_at TIMESTAMP,
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

CREATE INDEX idx_fraud_alerts_customer_id ON fraud_alerts(customer_id);
CREATE INDEX idx_fraud_alerts_severity ON fraud_alerts(severity);
CREATE INDEX idx_fraud_alerts_status ON fraud_alerts(status);
CREATE INDEX idx_fraud_alerts_created_at ON fraud_alerts(created_at);

-- ============================================
-- 10. COMPLIANCE CHECKS (GDPR, AML, KYC)
-- ============================================
CREATE TABLE compliance_checks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  
  -- Check type
  check_type VARCHAR(50) NOT NULL, -- 'kyc', 'aml', 'gdpr', 'sanctions', 'pep'
  
  -- Results
  passed BOOLEAN,
  result_description TEXT,
  result_details JSONB,
  
  -- Manual review
  requires_manual_review BOOLEAN DEFAULT false,
  reviewed_by UUID,
  reviewed_at TIMESTAMP,
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

CREATE INDEX idx_compliance_customer_id ON compliance_checks(customer_id);
CREATE INDEX idx_compliance_check_type ON compliance_checks(check_type);
CREATE INDEX idx_compliance_passed ON compliance_checks(passed);

-- ============================================
-- ROW LEVEL SECURITY (GDPR Compliance)
-- ============================================

-- Enable RLS on sensitive tables
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_interactions ENABLE ROW LEVEL SECURITY;

-- Policy: Customers can only see their own data
CREATE POLICY "Users can view their own customer record"
  ON customers
  FOR SELECT
  USING (auth.uid()::text = id::text);

CREATE POLICY "Users can view their own accounts"
  ON accounts
  FOR SELECT
  USING (auth.uid()::text = customer_id::text);

CREATE POLICY "Users can view their own cards"
  ON cards
  FOR SELECT
  USING (auth.uid()::text = customer_id::text);

CREATE POLICY "Users can view their own transactions"
  ON transactions
  FOR SELECT
  USING (auth.uid()::text = customer_id::text);

-- ============================================
-- FUNCTIONS & TRIGGERS
-- ============================================

-- Function: Automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to update tables
CREATE TRIGGER update_customers_updated_at BEFORE UPDATE ON customers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_accounts_updated_at BEFORE UPDATE ON accounts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_cards_updated_at BEFORE UPDATE ON cards
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON transactions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function: Log all changes to audit_logs
CREATE OR REPLACE FUNCTION log_audit_event()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_logs (
    customer_id,
    action_type,
    resource_type,
    resource_id,
    action_description,
    old_values,
    new_values
  ) VALUES (
    COALESCE(NEW.customer_id, OLD.customer_id),
    TG_ARGV[0],
    TG_TABLE_NAME,
    COALESCE(NEW.id, OLD.id),
    'Record ' || TG_OP,
    to_jsonb(OLD),
    to_jsonb(NEW)
  );
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Apply audit logging to sensitive tables
CREATE TRIGGER audit_accounts
  AFTER INSERT OR UPDATE OR DELETE ON accounts
  FOR EACH ROW EXECUTE FUNCTION log_audit_event('account_modified');

CREATE TRIGGER audit_cards
  AFTER INSERT OR UPDATE OR DELETE ON cards
  FOR EACH ROW EXECUTE FUNCTION log_audit_event('card_modified');

CREATE TRIGGER audit_transactions
  AFTER INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW EXECUTE FUNCTION log_audit_event('transaction_created');