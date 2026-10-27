CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY,
  phone TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  is_blocked BOOLEAN DEFAULT FALSE,
  kyc_status TEXT DEFAULT 'none',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE wallets (
  user_id BIGINT PRIMARY KEY REFERENCES users(id),
  balance BIGINT NOT NULL DEFAULT 0 CHECK (balance >= 0)  -- RWF
);

CREATE TABLE ledger_entries (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  type TEXT NOT NULL,             -- deposit | bet | win | withdrawal | adjust
  amount BIGINT NOT NULL,         -- signed: debit negative
  balance_after BIGINT NOT NULL,
  ref TEXT,                       -- bet id / payment id
  idem_key TEXT UNIQUE,           -- prevents double processing
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE seed_chain (idx INT PRIMARY KEY, seed TEXT NOT NULL);

CREATE TABLE rounds (
  id BIGSERIAL PRIMARY KEY,
  seed_idx INT NOT NULL,
  seed_hash TEXT NOT NULL,        -- shown before round
  seed TEXT,                      -- revealed after crash
  crash_point NUMERIC(10,2),
  started_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE bets (
  id BIGSERIAL PRIMARY KEY,
  round_id BIGINT REFERENCES rounds(id),
  user_id BIGINT REFERENCES users(id),
  amount BIGINT NOT NULL,
  auto_cashout NUMERIC(10,2),
  cashout_mult NUMERIC(10,2),
  payout BIGINT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON bets(user_id, created_at DESC);

CREATE TABLE deposits (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT REFERENCES users(id),
  method TEXT NOT NULL,           -- momo | crypto
  provider_ref TEXT UNIQUE,
  amount_rwf BIGINT,
  status TEXT DEFAULT 'pending',  -- pending | completed | failed
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE withdrawals (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT REFERENCES users(id),
  method TEXT NOT NULL,
  destination TEXT NOT NULL,      -- phone or crypto address
  amount_rwf BIGINT NOT NULL,
  status TEXT DEFAULT 'pending',  -- pending | approved | paid | rejected
  created_at TIMESTAMPTZ DEFAULT now()
);