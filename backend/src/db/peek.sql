CREATE TABLE IF NOT EXISTS peek_classes (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  bets INT NOT NULL CHECK (bets >= 1),
  skips INT NOT NULL CHECK (skips >= 0),
  max_stake BIGINT NOT NULL,
  max_mult NUMERIC(6,2) NOT NULL DEFAULT 10,
  price BIGINT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS user_peeks (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  class_id INT NOT NULL REFERENCES peek_classes(id),
  bets_left INT NOT NULL,
  skips_left INT NOT NULL,
  max_stake BIGINT NOT NULL,          -- snapshot: editing a class never changes classes already sold
  max_mult NUMERIC(6,2) NOT NULL,
  price_paid BIGINT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'scheduled',   -- scheduled | open | ended | cancelled
  opens_at TIMESTAMPTZ NOT NULL,
  opened_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  ended_reason TEXT,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS one_live_peek_per_user ON user_peeks(user_id) WHERE status IN ('scheduled','open');

ALTER TABLE bets ADD COLUMN IF NOT EXISTS peek_id BIGINT;

INSERT INTO peek_classes(name,bets,skips,max_stake,max_mult,price) VALUES
  ('Starter',3,3,3000,10,50000),
  ('Silver',5,5,6000,10,175000),
  ('Gold',10,10,12000,10,705000),
  ('Platinum',20,20,25000,10,3000000)
ON CONFLICT (name) DO NOTHING;