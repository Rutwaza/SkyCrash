import { Router } from 'express';
import crypto from 'crypto';
import { pool } from '../db/pool';
import { cfg } from '../config';
import { requireAuth } from './auth';
import { applyDelta } from '../services/wallet';
import { notifyUser } from '../services/realtime';
import { tg } from '../services/telegram';
import { getEngine } from '../services/realtime';
import { approvePeekOrder } from '../services/peek';

export const payments = Router();
const NP = 'https://api.nowpayments.io/v1';   // sandbox: https://api-sandbox.nowpayments.io/v1
const n = (x: number) => x.toLocaleString('en-US');

const sortKeys = (o: any): any =>
  Array.isArray(o) ? o.map(sortKeys)
  : o && typeof o === 'object' ? Object.keys(o).sort().reduce((a: any, k) => (a[k] = sortKeys(o[k]), a), {})
  : o;

function validSig(body: any, sig?: string) {
  if (!sig) return false;
  const h = crypto.createHmac('sha512', cfg.npIpn).update(JSON.stringify(sortKeys(body))).digest('hex');
  return h.length === sig.length && crypto.timingSafeEqual(Buffer.from(h), Buffer.from(sig));
}

// ---------- deposit request ----------
payments.post('/deposit', requireAuth, async (req: any, res) => {
  const { method, amount } = req.body;
  if (!['momo', 'crypto'].includes(method) || !Number.isInteger(amount) || amount < cfg.minDeposit || amount > cfg.maxDeposit)
    return res.status(400).json({ error: 'invalid', detail: `Amount must be ${cfg.minDeposit}-${cfg.maxDeposit} RWF` });

  const pend = await pool.query(
    `SELECT count(*)::int AS n FROM deposits WHERE user_id=$1 AND status='pending' AND created_at > now() - interval '24 hours'`, [req.uid]);
  if (pend.rows[0].n >= 5)
    return res.status(429).json({ error: 'too_many_pending', detail: 'You have too many pending deposits. Please wait for approval.' });

  const ref = crypto.randomUUID();
  const code = ref.slice(0, 6).toUpperCase();
  const ins = await pool.query(
    'INSERT INTO deposits(user_id,method,provider_ref,amount_rwf) VALUES($1,$2,$3,$4) RETURNING id', [req.uid, method, ref, amount]);
  const id = ins.rows[0].id;
  const phone = (await pool.query('SELECT phone FROM users WHERE id=$1', [req.uid])).rows[0].phone;

  if (method === 'momo') {
    tg(`SKYCRASH ${phone} - ${n(amount)} RWF - DEPOSIT REQUEST\nMethod: MoMo | Ref ${code} | #${id}`);
    return res.json({ ref, code, payTo: cfg.momoNumber, next: 'manual' });
  }

  const r = await fetch(`${NP}/payment`, {
    method: 'POST',
    headers: { 'x-api-key': cfg.npKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      price_amount: +(amount / cfg.usdRwf).toFixed(2),
      price_currency: 'usd',
      pay_currency: 'usdttrc20',
      order_id: ref,
      ipn_callback_url: `${cfg.publicUrl}/api/pay/webhook/nowpayments`,
    }),
  });
  const p: any = await r.json();
  if (!r.ok) {
    console.error('NOWPayments error', p);
    await pool.query(`UPDATE deposits SET status='failed', note='provider error' WHERE id=$1`, [id]);
    return res.status(502).json({ error: 'provider_error', detail: p.message });
  }
  tg(`SKYCRASH ${phone} - ${n(amount)} RWF - DEPOSIT REQUEST\nMethod: Crypto USDT | Ref ${code} | #${id}`);
  res.json({ ref, address: p.pay_address, payAmount: p.pay_amount, currency: p.pay_currency });
});

// ---------- crypto webhook (auto-credit when NOWPayments confirms) ----------
payments.post('/webhook/nowpayments', async (req, res) => {

  if (!validSig(req.body, req.headers['x-nowpayments-sig'] as string)) return res.sendStatus(401);
  const { order_id, payment_status } = req.body;
  if (payment_status !== 'finished') return res.sendStatus(200);

  if (String(order_id).startsWith('pk_')) {
    const ref = order_id.slice(3);
    const ord = await pool.query(`SELECT * FROM peek_orders WHERE provider_ref=$1 AND status='pending'`, [ref]);
    if (ord.rowCount) await approvePeekOrder(ord.rows[0]);   // shared helper, see admin.ts below
    return res.sendStatus(200);
  }

  const c = await pool.connect();
  let credited: { user_id: number; amount: number; bal: number } | null = null;
  try {
    await c.query('BEGIN');
    const d = await c.query(
      `UPDATE deposits SET status='completed', reviewed_at=now()
       WHERE provider_ref=$1 AND status='pending' AND method='crypto' RETURNING user_id, amount_rwf`, [order_id]);
    if (d.rowCount) {
      const bal = await applyDelta(c, +d.rows[0].user_id, +d.rows[0].amount_rwf, 'deposit', order_id, `dep:${order_id}`);
      credited = { user_id: +d.rows[0].user_id, amount: +d.rows[0].amount_rwf, bal };
    }
    await c.query('COMMIT');
  } catch (e) { await c.query('ROLLBACK'); console.error(e); return res.sendStatus(500); }
  finally { c.release(); }

  if (credited) {
    notifyUser(credited.user_id, { balance: credited.bal, text: `Deposit confirmed: +${n(credited.amount)} RWF` });
    const phone = (await pool.query('SELECT phone FROM users WHERE id=$1', [credited.user_id])).rows[0].phone;
    tg(`SKYCRASH ${phone} - ${n(credited.amount)} RWF - CRYPTO DEPOSIT CONFIRMED (auto-credited)`);
  }
  res.sendStatus(200);
});

// ---------- withdrawal request (balance locked now, you pay manually later) ----------
payments.post('/withdraw', requireAuth, async (req: any, res) => {
  const { method, amount } = req.body;
  const destination = String(req.body.destination ?? '').trim().slice(0, 100);
  if (!['momo', 'crypto'].includes(method) || !destination || !Number.isInteger(amount) || amount < cfg.minWithdraw || amount > cfg.maxWithdraw)
    return res.status(400).json({ error: 'invalid', detail: `Amount must be ${cfg.minWithdraw}-${cfg.maxWithdraw} RWF` });

  const c = await pool.connect();
  let id = 0;
  try {
    await c.query('BEGIN');
    const w = await c.query(
      'INSERT INTO withdrawals(user_id,method,destination,amount_rwf) VALUES($1,$2,$3,$4) RETURNING id',
      [req.uid, method, destination, amount]);
    id = w.rows[0].id;
    await applyDelta(c, req.uid, -amount, 'withdrawal', String(id));
    await c.query('COMMIT');
  } catch (e: any) { await c.query('ROLLBACK'); return res.status(400).json({ error: e.message }); }
  finally { c.release(); }

  const phone = (await pool.query('SELECT phone FROM users WHERE id=$1', [req.uid])).rows[0].phone;
  tg(`SKYCRASH ${phone} - ${n(amount)} RWF - WITHDRAW REQUEST\nMethod: ${method === 'momo' ? 'MoMo' : 'Crypto USDT'} | To: ${destination} | #${id}`);
  res.json({ status: 'pending' });
});

// ---------- list classes (for the app's buy page) ----------
payments.get('/peek/classes', requireAuth, async (_req, res) => {
  const r = await pool.query('SELECT id,name,predictions,max_mult,price FROM peek_classes WHERE active ORDER BY price');
  res.json(r.rows);
});

// ---------- buy a class ----------
payments.post('/peek/buy', requireAuth, async (req: any, res) => {
  const { classId, method } = req.body;    // method: 'momo' | 'crypto' | 'wallet'
  if (!['momo', 'crypto', 'wallet'].includes(method)) return res.status(400).json({ error: 'invalid' });
  const cls = await pool.query('SELECT * FROM peek_classes WHERE id=$1 AND active', [+classId]);
  if (!cls.rowCount) return res.status(404).json({ error: 'Class not found' });
  const c = cls.rows[0];
  const phone = (await pool.query('SELECT phone FROM users WHERE id=$1', [req.uid])).rows[0].phone;

  if (method === 'wallet') {
    const w = await pool.query('SELECT balance FROM wallets WHERE user_id=$1', [req.uid]);
    if (+w.rows[0].balance < +c.price) return res.status(400).json({ error: 'insufficient_balance' });
    const conn = await pool.connect();
    try {
      await conn.query('BEGIN');
      const bal = await applyDelta(conn, req.uid, -c.price, 'peek_purchase', `cls:${c.id}`);
      await conn.query(
        `INSERT INTO user_peeks(user_id,class_id,predictions_left,max_mult,price_paid,opens_at)
         VALUES($1,$2,$3,$4,$5, now() + make_interval(secs => $6::int))`,
        [req.uid, c.id, c.predictions, c.max_mult, c.price, cfg.peekDefaultDelaySec]);
      await pool.query(
        `INSERT INTO peek_orders(user_id,class_id,method,amount,status,reviewed_at) VALUES($1,$2,'wallet',$3,'approved',now())`,
        [req.uid, c.id, c.price]);
      await conn.query('COMMIT');
      await getEngine()?.peekRefresh(req.uid);
      tg(`SKYCRASH ${phone} - WALLET PURCHASE: ${c.name} (${n(c.price)} RWF)`);
      return res.json({ ok: true, balance: bal });
    } catch (e: any) {
      await conn.query('ROLLBACK');
      if (e.message === 'INSUFFICIENT_FUNDS') return res.status(400).json({ error: 'insufficient_balance' });
      if (e.code === '23505') return res.status(409).json({ error: 'You already have an active pack - finish it first' });
      return res.status(500).json({ error: e.message });
    } finally { conn.release(); }
  }

  // momo / crypto: creates a PENDING order, same approval pattern as deposits
  const already = await pool.query(
    `SELECT 1 FROM user_peeks WHERE user_id=$1 AND status IN ('scheduled','open')`, [req.uid]);
  if (already.rowCount) return res.status(409).json({ error: 'You already have an active pack' });

  const ref = crypto.randomUUID();
  await pool.query(
    'INSERT INTO peek_orders(user_id,class_id,method,amount,provider_ref) VALUES($1,$2,$3,$4,$5)',
    [req.uid, c.id, method, c.price, ref]);

  if (method === 'momo') {
    tg(`SKYCRASH ${phone} - PREDICTOR ORDER: ${c.name} - ${n(c.price)} RWF - MOMO\nRef ${ref.slice(0,6).toUpperCase()}`);
    return res.json({ ref, code: ref.slice(0, 6).toUpperCase(), payTo: cfg.momoNumber, next: 'manual' });
  }

  const r = await fetch(`${NP}/payment`, {
    method: 'POST',
    headers: { 'x-api-key': cfg.npKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      price_amount: +(c.price / cfg.usdRwf).toFixed(2), price_currency: 'usd', pay_currency: 'usdttrc20',
      order_id: 'pk_' + ref, ipn_callback_url: `${cfg.publicUrl}/api/pay/webhook/nowpayments`,
    }),
  });
  const p: any = await r.json();
  if (!r.ok) { await pool.query(`UPDATE peek_orders SET status='rejected', note='provider error' WHERE provider_ref=$1`, [ref]); return res.status(502).json({ error: 'provider_error' }); }
  tg(`SKYCRASH ${phone} - PREDICTOR ORDER: ${c.name} - ${n(c.price)} RWF - CRYPTO\nRef ${ref.slice(0,6).toUpperCase()}`);
  res.json({ ref, address: p.pay_address, payAmount: p.pay_amount, currency: p.pay_currency });
});