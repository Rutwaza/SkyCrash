import { Router } from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import { pool } from '../db/pool';
import { cfg } from '../config';

export const auth = Router();
const body = z.object({ phone: z.string().regex(/^\+250\d{9}$/), password: z.string().min(4).max(64) });

auth.post('/register', async (req, res) => {
  const p = body.safeParse(req.body); if (!p.success) return res.status(400).json({ error: 'invalid' });
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const u = await c.query('INSERT INTO users(phone,password_hash) VALUES($1,$2) RETURNING id',
      [p.data.phone, await bcrypt.hash(p.data.password, 10)]);
    await c.query('INSERT INTO wallets(user_id) VALUES($1)', [u.rows[0].id]);
    await c.query('COMMIT');
    res.json({ token: jwt.sign({ id: +u.rows[0].id }, cfg.jwt, { expiresIn: '7d' }) });
  } catch { await c.query('ROLLBACK'); res.status(409).json({ error: 'exists' }); } finally { c.release(); }
});

auth.post('/login', async (req, res) => {
  const p = body.safeParse(req.body); if (!p.success) return res.status(400).json({ error: 'invalid' });
  const u = await pool.query('SELECT * FROM users WHERE phone=$1', [p.data.phone]);
  if (!u.rowCount || u.rows[0].is_blocked || !(await bcrypt.compare(p.data.password, u.rows[0].password_hash)))
    return res.status(401).json({ error: 'bad credentials' });
  res.json({ token: jwt.sign({ id: +u.rows[0].id }, cfg.jwt, { expiresIn: '7d' }) });
});

export function requireAuth(req: any, res: any, next: any) {
  try { req.uid = (jwt.verify((req.headers.authorization || '').replace('Bearer ', ''), cfg.jwt) as any).id; next(); }
  catch { res.status(401).json({ error: 'unauthorized' }); }
}