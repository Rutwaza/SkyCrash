import express from 'express';
import http from 'http';
import path from 'path';
import cors from 'cors';
import jwt from 'jsonwebtoken';
import { Server } from 'socket.io';
import { cfg } from './config';
import { pool } from './db/pool';
import { auth } from './routes/auth';
import { history } from './routes/history';
import { payments } from './routes/payments';
import { admin } from './routes/admin';
import { Engine } from './services/engine';
import { setIO, setEngine } from './services/realtime';
import { mask } from './services/util';
import { set } from 'zod';

const app = express();
app.use(cors(), express.json());
app.use('/api/auth', auth);
app.use('/api/me', history);
app.use('/api/pay', payments);
app.use('/api/admin', admin);
app.get('/admin', (_req, res) => res.sendFile(path.join(__dirname, '..', 'admin', 'index.html')));
app.get('/admin/peek', (_req, res) => res.sendFile(path.join(__dirname, '..', 'admin', 'peek.html')));

app.get('/api/top-wins', async (_req, res) => {
  const r = await pool.query(
    `SELECT user_id, amount, cashout_mult, payout FROM bets
     WHERE payout > 0 AND created_at > now() - interval '24 hours'
     ORDER BY payout DESC LIMIT 8`);
  res.json(r.rows.map(x => ({ user: mask(+x.user_id), amount: +x.amount, m: +x.cashout_mult, payout: +x.payout })));
});

app.get('/api/recent-rounds', async (_req, res) => {
  const r = await pool.query('SELECT crash_point FROM rounds WHERE crash_point IS NOT NULL ORDER BY id DESC LIMIT 20');
  res.json(r.rows.map(x => +x.crash_point));
});

const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });
setIO(io);
const engine = new Engine(io);
setEngine(engine);
io.use((s, next) => {
  try { (s as any).uid = (jwt.verify(String(s.handshake.auth.token), cfg.jwt) as any).id; next(); }
  catch { next(new Error('unauthorized')); }
});

io.on('connection', async socket => {
  const uid = (socket as any).uid;
  socket.join(`user:${uid}`);                       // lets admin approvals reach this player live
  socket.on('bet', async (d, ack) => {
    try { ack({ ok: true, ...(await engine.placeBet(uid, socket.id, +d.amount, d.auto ? +d.auto : undefined)) }); }
    catch (e: any) { ack({ ok: false, error: e.message }); }
  });
  socket.on('cashout', async (d, ack) => {
    try { ack({ ok: true, ...(await engine.cashout(uid, +d.betId)) }); }
    catch (e: any) { ack({ ok: false, error: e.message }); }
  });

  const h = await pool.query('SELECT crash_point FROM rounds WHERE crash_point IS NOT NULL ORDER BY id DESC LIMIT 30');
  socket.emit('snapshot', { ...engine.snapshot(), history: h.rows.map(r => +r.crash_point) });
  engine.peekOnConnect(uid, socket.id);
});

server.listen(cfg.port, () => { console.log('SkyCrash on', cfg.port); engine.start(); });