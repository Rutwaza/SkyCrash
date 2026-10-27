import { Router } from 'express';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { pool } from '../db/pool';
import { cfg } from '../config';
import { applyDelta } from '../services/wallet';
import { notifyUser } from '../services/realtime';
import { tg } from '../services/telegram';
import { quotePerK } from '../services/peekPricing';
import { getEngine } from '../services/realtime';
import { approvePeekOrder } from '../services/peek';

export const admin = Router();
const n = (x: number) => x.toLocaleString('en-US');

// ---------- login (separate from player accounts) ----------
const attempts = new Map<string, { n: number; t: number }>();

admin.post('/login', (req, res) => {
  const ip = String(req.headers['cf-connecting-ip'] || req.ip || 'unknown');
  const now = Date.now();
  const rec = attempts.get(ip);
  const fresh = !rec || now - rec.t > 15 * 60_000;
  if (!fresh && rec!.n >= 8) return res.status(429).json({ error: 'Too many attempts, wait 15 minutes' });

  const A = Buffer.from(String(req.body?.password ?? ''));
  const B = Buffer.from(cfg.adminPassword);
  const ok = cfg.adminPassword.length >= 8 && A.length === B.length && crypto.timingSafeEqual(A, B);
  if (!ok) {
    attempts.set(ip, fresh ? { n: 1, t: now } : { n: rec!.n + 1, t: rec!.t });
    return res.status(401).json({ error: 'Wrong password' });
  }
  attempts.delete(ip);
  tg(`SKYCRASH ADMIN LOGIN from ${ip}`);
  res.json({ token: jwt.sign({ role: 'admin' }, cfg.jwt, { expiresIn: '8h' }) });
});

function requireAdmin(req: any, res: any, next: any) {
  try {
    const p: any = jwt.verify((req.headers.authorization || '').replace('Bearer ', ''), cfg.jwt);
    if (p.role !== 'admin') throw new Error('not admin');   // player tokens have no role
    next();
  } catch { res.status(401).json({ error: 'unauthorized' }); }
}
admin.use(requireAdmin);

// ---------- summary ----------
const DAY = `(date_trunc('day', now() AT TIME ZONE 'Africa/Kigali') AT TIME ZONE 'Africa/Kigali')`;

admin.get('/summary', async (_req, res) => {
  const v = async (sql: string) => +(await pool.query(sql)).rows[0].v;
  const betsToday = await v(`SELECT COALESCE(SUM(amount),0) v FROM bets WHERE created_at >= ${DAY}`);
  const payoutsToday = await v(`SELECT COALESCE(SUM(payout),0) v FROM bets WHERE created_at >= ${DAY}`);
  res.json({
    depositsToday: await v(`SELECT COALESCE(SUM(amount_rwf),0) v FROM deposits WHERE status='completed' AND reviewed_at >= ${DAY}`),
    withdrawalsToday: await v(`SELECT COALESCE(SUM(amount_rwf),0) v FROM withdrawals WHERE status='paid' AND reviewed_at >= ${DAY}`),
    pendingDeposits: await v(`SELECT count(*) v FROM deposits WHERE status='pending'`),
    pendingWithdrawals: await v(`SELECT count(*) v FROM withdrawals WHERE status='pending'`),
    playerBalances: await v(`SELECT COALESCE(SUM(balance),0) v FROM wallets`),
    betsToday, payoutsToday, houseProfitToday: betsToday - payoutsToday,
  });
});

// ---------- deposits ----------
admin.get('/deposits', async (req, res) => {
  const status = String(req.query.status || 'pending');
  const r = await pool.query(
    `SELECT d.id, d.method, d.amount_rwf, d.status, d.provider_ref, d.created_at, d.reviewed_at, d.note, u.phone
     FROM deposits d JOIN users u ON u.id = d.user_id
     WHERE ($1 = 'all' OR d.status = $1) ORDER BY d.id DESC LIMIT 200`, [status]);
  res.json(r.rows);
});

admin.post('/deposits/:id/approve', async (req, res) => {
  const id = +req.params.id;
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const cur = await c.query(`SELECT * FROM deposits WHERE id=$1 AND status='pending' FOR UPDATE`, [id]);
    if (!cur.rowCount) { await c.query('ROLLBACK'); return res.status(409).json({ error: 'Not pending (already handled?)' }); }
    const d = cur.rows[0];
    const amount = req.body?.amount !== undefined ? +req.body.amount : +d.amount_rwf;   // amount actually received
    if (!Number.isInteger(amount) || amount < 1 || amount > cfg.maxDeposit) {
      await c.query('ROLLBACK'); return res.status(400).json({ error: 'Invalid amount' });
    }
    await c.query(`UPDATE deposits SET status='completed', amount_rwf=$1, reviewed_at=now(), note=$2 WHERE id=$3`,
      [amount, String(req.body?.note ?? '').slice(0, 200), id]);
    // same idempotency key as the crypto webhook => can never be credited twice
    const bal = await applyDelta(c, +d.user_id, amount, 'deposit', String(d.provider_ref), `dep:${d.provider_ref}`);
    await c.query('COMMIT');
    notifyUser(+d.user_id, { balance: bal, text: `Deposit approved: +${n(amount)} RWF` });
    res.json({ ok: true, balance: bal });
  } catch (e: any) { await c.query('ROLLBACK').catch(() => {}); res.status(500).json({ error: e.message }); }
  finally { c.release(); }
});

admin.post('/deposits/:id/reject', async (req, res) => {
  const r = await pool.query(
    `UPDATE deposits SET status='failed', reviewed_at=now(), note=$2 WHERE id=$1 AND status='pending' RETURNING user_id, amount_rwf`,
    [+req.params.id, String(req.body?.note ?? '').slice(0, 200)]);
  if (!r.rowCount) return res.status(409).json({ error: 'Not pending' });
  notifyUser(+r.rows[0].user_id, { text: `Deposit of ${n(+r.rows[0].amount_rwf)} RWF was not confirmed` });
  res.json({ ok: true });
});

// ---------- withdrawals ----------
admin.get('/withdrawals', async (req, res) => {
  const status = String(req.query.status || 'pending');
  const r = await pool.query(
    `SELECT w.id, w.method, w.destination, w.amount_rwf, w.status, w.created_at, w.reviewed_at, w.note, u.phone
     FROM withdrawals w JOIN users u ON u.id = w.user_id
     WHERE ($1 = 'all' OR w.status = $1) ORDER BY w.id DESC LIMIT 200`, [status]);
  res.json(r.rows);
});

// you already sent the money manually -> mark as paid
admin.post('/withdrawals/:id/paid', async (req, res) => {
  const r = await pool.query(
    `UPDATE withdrawals SET status='paid', reviewed_at=now(), note=$2 WHERE id=$1 AND status='pending' RETURNING user_id, amount_rwf`,
    [+req.params.id, String(req.body?.note ?? '').slice(0, 200)]);
  if (!r.rowCount) return res.status(409).json({ error: 'Not pending' });
  notifyUser(+r.rows[0].user_id, { text: `Withdrawal paid: ${n(+r.rows[0].amount_rwf)} RWF` });
  res.json({ ok: true });
});

// reject -> money returns to the player's balance
admin.post('/withdrawals/:id/reject', async (req, res) => {
  const id = +req.params.id;
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const r = await c.query(
      `UPDATE withdrawals SET status='rejected', reviewed_at=now(), note=$2 WHERE id=$1 AND status='pending' RETURNING user_id, amount_rwf`,
      [id, String(req.body?.note ?? '').slice(0, 200)]);
    if (!r.rowCount) { await c.query('ROLLBACK'); return res.status(409).json({ error: 'Not pending' }); }
    const bal = await applyDelta(c, +r.rows[0].user_id, +r.rows[0].amount_rwf, 'refund', `wd:${id}`, `wdrefund:${id}`);
    await c.query('COMMIT');
    notifyUser(+r.rows[0].user_id, { balance: bal, text: `Withdrawal rejected - ${n(+r.rows[0].amount_rwf)} RWF returned to your balance` });
    res.json({ ok: true });
  } catch (e: any) { await c.query('ROLLBACK').catch(() => {}); res.status(500).json({ error: e.message }); }
  finally { c.release(); }
});

// ---------- users (read-only) ----------
admin.get('/users', async (req, res) => {
  const r = await pool.query(
    `SELECT u.id, u.phone, u.created_at, w.balance FROM users u JOIN wallets w ON w.user_id = u.id
     WHERE u.phone LIKE $1 ORDER BY u.id DESC LIMIT 100`, [`%${String(req.query.q || '')}%`]);
  res.json(r.rows);
});

// ===================== PREDICTOR CLASSES =====================
const wrap = (fn: (req: any, res: any) => Promise<any>) => (req: any, res: any) =>
  fn(req, res).catch((e: any) => res.status(500).json({ error: e.message }));
const phoneNorm = (p: string) => { const d = String(p).replace(/\D/g, ''); return d.length >= 9 ? '+250' + d.slice(-9) : ''; };

admin.get('/peek/classes', wrap(async (_req, res) => {
  res.json((await pool.query('SELECT * FROM peek_classes ORDER BY price')).rows);
}));

admin.post('/peek/classes', wrap(async (req, res) => {
  const b = req.body || {};
  const name = String(b.name || '').trim().slice(0, 40);
  const predictions = +b.predictions, maxMult = +b.maxMult, price = +b.price;
  if (!name || !Number.isInteger(predictions) || predictions < 1 || predictions > 60 ||
      !(maxMult >= 1.5 && maxMult <= 100) || !Number.isInteger(price) || price < 0)
    return res.status(400).json({ error: 'Invalid values' });
  try {
    if (b.id) await pool.query(
      'UPDATE peek_classes SET name=$1,predictions=$2,max_mult=$3,price=$4,active=$5 WHERE id=$6',
      [name, predictions, maxMult, price, b.active !== false, +b.id]);
    else await pool.query(
      'INSERT INTO peek_classes(name,predictions,max_mult,price,active) VALUES($1,$2,$3,$4,$5)',
      [name, predictions, maxMult, price, b.active !== false]);
  } catch (e: any) {
    if (e.code === '23505') return res.status(409).json({ error: 'A class with that name already exists' });
    throw e;
  }
  res.json({ ok: true });
}));

admin.get('/peek/quote', wrap(async (req, res) => {
  const predictions = +req.query.predictions, mult = +req.query.mult;
  if (!(predictions >= 1 && predictions <= 60) || !(mult >= 1.5 && mult <= 100))
    return res.status(400).json({ error: 'Out of range (max 60 predictions)' });
  res.json(quotePerK(predictions, mult));
}));

admin.get('/peek/list', wrap(async (req, res) => {
  const all = req.query.status === 'all';
  const r = await pool.query(
    `SELECT up.*, pc.name, u.phone FROM user_peeks up
     JOIN peek_classes pc ON pc.id = up.class_id JOIN users u ON u.id = up.user_id
     WHERE ($1 OR up.status IN ('scheduled','open')) ORDER BY up.id DESC LIMIT 200`, [all]);
  res.json(r.rows);
}));

admin.post('/peek/assign', wrap(async (req, res) => {
  const phone = phoneNorm(req.body?.phone);
  const cls = await pool.query('SELECT * FROM peek_classes WHERE id=$1 AND active', [+req.body?.classId]);
  const usr = await pool.query('SELECT id FROM users WHERE phone=$1', [phone]);
  if (!cls.rowCount || !usr.rowCount) return res.status(404).json({ error: 'User or class not found' });
  const c = cls.rows[0];
  const delay = Math.min(600, Math.max(5, Math.round(+req.body?.delaySec || cfg.peekDefaultDelaySec)));
  const paid = req.body?.pricePaid !== undefined && req.body.pricePaid !== '' ? +req.body.pricePaid : +c.price;
  if (!Number.isFinite(paid) || paid < 0) return res.status(400).json({ error: 'Invalid price' });
  try {
    await pool.query(
      `INSERT INTO user_peeks(user_id,class_id,predictions_left,max_mult,price_paid,opens_at,note)
       VALUES($1,$2,$3,$4,$5, now() + make_interval(secs => $6::int), $7)`,
      [usr.rows[0].id, c.id, c.predictions, c.max_mult, Math.round(paid), delay, String(req.body?.note ?? '').slice(0, 200)]);
  } catch (e: any) {
    if (e.code === '23505') return res.status(409).json({ error: 'This user already has an active pack - finish/disable it first' });
    throw e;
  }
  await getEngine()?.peekRefresh(+usr.rows[0].id);
  tg(`SKYCRASH ${phone} - PREDICTOR PACK ENABLED: ${c.name} (sold ${n(Math.round(paid))} RWF)`);
  res.json({ ok: true });
}));

admin.post('/peek/:id/disable', wrap(async (req, res) => {
  const r = await pool.query(
    `UPDATE user_peeks SET status='cancelled', ended_reason='disabled by admin', ended_at=now()
     WHERE id=$1 AND status IN ('scheduled','open') RETURNING user_id`, [+req.params.id]);
  if (!r.rowCount) return res.status(409).json({ error: 'Not live' });
  await getEngine()?.peekRefresh(+r.rows[0].user_id);
  res.json({ ok: true });
}));

admin.get('/peek/stats', wrap(async (_req, res) => {
  const v = async (sql: string) => +(await pool.query(sql)).rows[0].v;
  const soldToday = await v(`SELECT COALESCE(SUM(price_paid),0) v FROM user_peeks WHERE created_at >= ${DAY}`);
  const profitPaidToday = await v(`SELECT COALESCE(SUM(GREATEST(payout-amount,0)),0) v FROM bets WHERE peek_id IS NOT NULL AND created_at >= ${DAY}`);
  res.json({ soldToday, profitPaidToday, budget: cfg.peekDailyBudget, paused: profitPaidToday >= cfg.peekDailyBudget });
}));

// ---- MoMo / crypto purchase orders (wallet purchases skip this - approved instantly) ----
admin.get('/peek/orders', wrap(async (req, res) => {
  const status = String(req.query.status || 'pending');
  const r = await pool.query(
    `SELECT po.*, pc.name, u.phone FROM peek_orders po
     JOIN peek_classes pc ON pc.id=po.class_id JOIN users u ON u.id=po.user_id
     WHERE ($1='all' OR po.status=$1) ORDER BY po.id DESC LIMIT 200`, [status]);
  res.json(r.rows);
}));

admin.post('/peek/orders/:id/approve', wrap(async (req, res) => {
  const r = await pool.query(`SELECT * FROM peek_orders WHERE id=$1 AND status='pending'`, [+req.params.id]);
  if (!r.rowCount) return res.status(409).json({ error: 'Not pending' });
  await approvePeekOrder(r.rows[0], String(req.body?.note ?? ''));
  res.json({ ok: true });
}));

admin.post('/peek/orders/:id/reject', wrap(async (req, res) => {
  const r = await pool.query(
    `UPDATE peek_orders SET status='rejected', reviewed_at=now(), note=$2 WHERE id=$1 AND status='pending' RETURNING user_id`,
    [+req.params.id, String(req.body?.note ?? '').slice(0, 200)]);
  if (!r.rowCount) return res.status(409).json({ error: 'Not pending' });
  res.json({ ok: true });
}));