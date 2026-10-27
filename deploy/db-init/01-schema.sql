-- Full schema for a FRESH database (runs once, on first start of the db container)
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
  balance BIGINT NOT NULL DEFAULT 0 CHECK (balance >= 0)
);

CREATE TABLE ledger_entries (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  type TEXT NOT NULL,
  amount BIGINT NOT NULL,
  balance_after BIGINT NOT NULL,
  ref TEXT,
  idem_key TEXT UNIQUE,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE seed_chain (idx INT PRIMARY KEY, seed TEXT NOT NULL);

CREATE TABLE rounds (
  id BIGSERIAL PRIMARY KEY,
  seed_idx INT NOT NULL,
  seed_hash TEXT NOT NULL,
  seed TEXT,
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
  created_at TIMESTAMPTZ DEFAULT now(),
  peek_id BIGINT
);
CREATE INDEX ON bets(user_id, created_at DESC);

CREATE TABLE deposits (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT REFERENCES users(id),
  method TEXT NOT NULL,
  provider_ref TEXT UNIQUE,
  amount_rwf BIGINT,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  note TEXT
);

CREATE TABLE withdrawals (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT REFERENCES users(id),
  method TEXT NOT NULL,
  destination TEXT NOT NULL,
  amount_rwf BIGINT NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  note TEXT
);

-- Peek classes
CREATE TABLE peek_classes (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  predictions INT NOT NULL CHECK (predictions >= 1),
  max_mult NUMERIC(6,2) NOT NULL DEFAULT 10,
  price BIGINT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE user_peeks (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  class_id INT NOT NULL REFERENCES peek_classes(id),
  predictions_left INT NOT NULL,
  max_mult NUMERIC(6,2) NOT NULL,
  price_paid BIGINT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'scheduled',
  opens_at TIMESTAMPTZ NOT NULL,
  opened_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  ended_reason TEXT,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX one_live_peek_per_user ON user_peeks(user_id) WHERE status IN ('scheduled','open');

CREATE TABLE peek_orders (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  class_id INT NOT NULL REFERENCES peek_classes(id),
  method TEXT NOT NULL,
  amount BIGINT NOT NULL,
  provider_ref TEXT UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  note TEXT
);

INSERT INTO peek_classes(name,predictions,max_mult,price) VALUES
  ('Starter',3,10,80000),
  ('Silver',10,10,500000),
  ('Gold',25,10,1150000),
  ('Platinum',50,10,2100000);