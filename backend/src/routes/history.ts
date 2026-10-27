import { Router } from 'express';
import { pool } from '../db/pool';
import { requireAuth } from './auth';

export const history = Router();
history.use(requireAuth);

history.get('/balance', async (req: any, res) => {
  const r = await pool.query('SELECT balance FROM wallets WHERE user_id=$1', [req.uid]);
  res.json({ balance: +r.rows[0].balance });
});
history.get('/bets', async (req: any, res) => {
  const r = await pool.query(
    `SELECT b.id, b.amount, b.cashout_mult, b.payout, r.crash_point, r.seed, b.created_at
     FROM bets b JOIN rounds r ON r.id=b.round_id WHERE b.user_id=$1 ORDER BY b.id DESC LIMIT 50`, [req.uid]);
  res.json(r.rows);
});
history.get('/transactions', async (req: any, res) => {
  const r = await pool.query(
    'SELECT type, amount, balance_after, created_at FROM ledger_entries WHERE user_id=$1 ORDER BY id DESC LIMIT 100', [req.uid]);
  res.json(r.rows);
});