import { Server } from 'socket.io';
import { pool } from '../db/pool';
import { cfg } from '../config';
import { crashPoint, multAt, sha256, timeForMult } from './fair';
import { applyDelta } from './wallet';
import { mask } from './util';

type Phase = 'BETTING' | 'RUNNING' | 'CRASHED';
interface LiveBet { id: number; userId: number; amount: number; auto?: number; done: boolean; socketId: string; peekId?: number; }
interface PeekState {
  id: number; userId: number; name: string; status: 'scheduled' | 'open';
  predictionsLeft: number; maxMult: number;
  opensAt: number; expiresAt: number | null;
}
const kigaliDay = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Africa/Kigali' });

export class Engine {
  phase: Phase = 'CRASHED';
  roundId = 0; seed = ''; crashAt = 1; startedAt = 0; seedIdx = 0; bettingEndsAt = 0;
  bets = new Map<number, LiveBet>();
  pendingUsers = new Set<number>();
  committed = 0;

  // ---- Peek classes ----
  peeks = new Map<number, PeekState>();     // userId -> live (scheduled/open) class
  peekSeen = new Set<number>();             // users who were shown THIS round's number
  peekProfitToday = 0;                      // class winnings paid today (for the daily budget)
  peekDay = kigaliDay();

  constructor(private io: Server) {}
  get peekPaused() { return this.peekProfitToday >= cfg.peekDailyBudget; }

  async start() {
    await this.recoverAbortedRounds();
    await this.loadPeeks();
    await this.loadPeekProfit();
    while (true) await this.runRound();
  }
  private sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
  private toUser(userId: number, ev: string, data: any) { this.io.to(`user:${userId}`).emit(ev, data); }
  private hasSockets(userId: number) { return (this.io.sockets.adapter.rooms.get(`user:${userId}`)?.size ?? 0) > 0; }

  stats() {
    let total = 0;
    const users = new Set<number>();
    for (const b of this.bets.values()) { total += b.amount; users.add(b.userId); }
    return { bettors: users.size, totalBet: total };
  }

  snapshot() {
    return {
      phase: this.phase, roundId: this.roundId,
      bettingLeft: this.phase === 'BETTING' ? Math.max(0, this.bettingEndsAt - Date.now()) : 0,
      bettingTotal: cfg.bettingMs,
      runningFor: this.phase === 'RUNNING' ? Date.now() - this.startedAt : 0,
      ...this.stats(),
      seedHash: this.seed ? sha256(this.seed) : null,
    };
  }

  // ================= round loop =================
  private async runRound() {
    const s = await pool.query(
      `SELECT idx, seed FROM seed_chain WHERE idx < COALESCE((SELECT MIN(seed_idx) FROM rounds), 1000000)
       ORDER BY idx DESC LIMIT 1`);
    this.seedIdx = s.rows[0].idx; this.seed = s.rows[0].seed;
    this.crashAt = crashPoint(this.seed, 'skycrash-v1');
    const r = await pool.query(
      'INSERT INTO rounds(seed_idx, seed_hash) VALUES($1,$2) RETURNING id', [this.seedIdx, sha256(this.seed)]);
    this.roundId = r.rows[0].id; this.bets.clear(); this.committed = 0;

    this.phase = 'BETTING';
    this.bettingEndsAt = Date.now() + cfg.bettingMs;
    this.io.emit('phase', {
      phase: 'BETTING', roundId: this.roundId, seedHash: sha256(this.seed), ms: cfg.bettingMs,
    });
    this.peekRoundStart().catch(e => console.error('peekRoundStart', e));   // after the phase event, not awaited
    await this.sleep(cfg.bettingMs);

    this.phase = 'RUNNING'; this.startedAt = Date.now();
    this.io.emit('phase', { phase: 'RUNNING' });
    const stopAt = timeForMult(this.crashAt);

    await new Promise<void>(resolve => {
      const t = setInterval(async () => {
        const el = Date.now() - this.startedAt;
        if (el >= stopAt) { clearInterval(t); resolve(); return; }
        const m = multAt(el);
        this.io.emit('tick', { m });
        for (const b of this.bets.values())
          if (!b.done && b.auto && m >= b.auto) await this.cashout(b.userId, b.id, b.auto).catch(() => {});
      }, 60);
    });

    this.phase = 'CRASHED';
    await pool.query('UPDATE rounds SET seed=$1, crash_point=$2 WHERE id=$3', [this.seed, this.crashAt, this.roundId]);
    this.io.emit('phase', { phase: 'CRASHED', crashAt: this.crashAt, seed: this.seed });
    await this.sleep(cfg.crashedMs);
  }

  // ================= bets =================
  async placeBet(userId: number, socketId: string, amount: number, auto?: number) {
    if (this.phase !== 'BETTING') throw new Error('BETTING_CLOSED');
    if (!Number.isInteger(amount) || amount < cfg.minBet || amount > cfg.maxBet) throw new Error('BAD_AMOUNT');
    if (auto !== undefined && !(auto >= 1.01)) throw new Error('BAD_AUTO');
    for (const b of this.bets.values()) if (b.userId === userId) throw new Error('ALREADY_BET');
    if (this.pendingUsers.has(userId)) throw new Error('ALREADY_BET');

    // Peek class caps: only while this user was actually shown this round's number
    // Peek: only while this user was actually shown this round's number — payout is capped, stake is not
    const st = this.peeks.get(userId);
    const peekBet = !!st && st.status === 'open' && this.peekSeen.has(userId);
    const autoEff = peekBet ? Math.min(auto ?? Infinity, st!.maxMult) : auto;   // forced cash-out at the class cap

    const worst = peekBet ? Math.floor(amount * st!.maxMult) : Math.min(cfg.maxWinPerBet, amount * 100);
    if (this.committed + worst > cfg.maxPayoutPerRound) throw new Error('ROUND_FULL');

    this.pendingUsers.add(userId);
    const c = await pool.connect();
    try {
      await c.query('BEGIN');
      const bet = await c.query(
        'INSERT INTO bets(round_id,user_id,amount,auto_cashout,peek_id) VALUES($1,$2,$3,$4,$5) RETURNING id',
        [this.roundId, userId, amount, autoEff ?? null, peekBet ? st!.id : null]);
      const id = +bet.rows[0].id;
      const bal = await applyDelta(c, userId, -amount, 'bet', String(id));
      await c.query('COMMIT');
      this.committed += worst;
      this.bets.set(id, { id, userId, amount, auto: autoEff, done: false, socketId, peekId: peekBet ? st!.id : undefined });
      this.io.emit('stats', this.stats());
      return { id, balance: bal };
    } catch (e) { await c.query('ROLLBACK'); throw e; }
    finally { c.release(); this.pendingUsers.delete(userId); }
  }

  async cashout(userId: number, betId: number, forced?: number) {
    const b = this.bets.get(betId);
    if (!b || b.userId !== userId || b.done || this.phase !== 'RUNNING') throw new Error('CANNOT_CASHOUT');
    const m = forced ?? multAt(Date.now() - this.startedAt);
    if (m >= this.crashAt) throw new Error('TOO_LATE');
    b.done = true;
    const payout = Math.min(Math.floor(b.amount * m), cfg.maxWinPerBet);
    const c = await pool.connect();
    try {
      await c.query('BEGIN');
      const bal = await applyDelta(c, userId, payout, 'win', String(betId), `win:${betId}`);
      await c.query('UPDATE bets SET cashout_mult=$1, payout=$2 WHERE id=$3', [m, payout, betId]);
      await c.query('COMMIT');
      if (b.peekId) this.peekProfitToday += Math.max(0, payout - b.amount);
      this.io.to(b.socketId).emit('cashed', { betId, m, payout, balance: bal });
      this.io.emit('win', { user: mask(userId), amount: b.amount, m, payout });
      return { m, payout, balance: bal };
    } catch (e) { b.done = false; await c.query('ROLLBACK'); throw e; }
    finally { c.release(); }
  }

    // ================= Peek classes =================
  private rowToState(x: any): PeekState {
    return {
      id: +x.id, userId: +x.user_id, name: x.name, status: x.status,
      predictionsLeft: +x.predictions_left, maxMult: +x.max_mult,
      opensAt: new Date(x.opens_at).getTime(), expiresAt: x.expires_at ? new Date(x.expires_at).getTime() : null,
    };
  }

  private peekPayload(st: PeekState, message?: string) {
    return {
      state: st.status, name: st.name, predictionsLeft: st.predictionsLeft, maxMult: st.maxMult,
      paused: this.peekPaused,
      opensInMs: Math.max(0, st.opensAt - Date.now()),
      expiresInMs: st.expiresAt ? Math.max(0, st.expiresAt - Date.now()) : null,
      message,
    };
  }

  async loadPeeks() {
    const r = await pool.query(
      `SELECT up.*, pc.name FROM user_peeks up JOIN peek_classes pc ON pc.id = up.class_id
       WHERE up.status IN ('scheduled','open')`);
    this.peeks.clear();
    for (const x of r.rows) this.peeks.set(+x.user_id, this.rowToState(x));
  }

  async loadPeekProfit() {
    const r = await pool.query(
      `SELECT COALESCE(SUM(GREATEST(payout - amount, 0)),0) AS v FROM bets
       WHERE peek_id IS NOT NULL AND created_at >= (date_trunc('day', now() AT TIME ZONE 'Africa/Kigali') AT TIME ZONE 'Africa/Kigali')`);
    this.peekProfitToday = +r.rows[0].v;
    this.peekDay = kigaliDay();
  }

  async peekRefresh(userId: number) {
    const r = await pool.query(
      `SELECT up.*, pc.name FROM user_peeks up JOIN peek_classes pc ON pc.id = up.class_id
       WHERE up.user_id=$1 AND up.status IN ('scheduled','open')`, [userId]);
    if (!r.rowCount) {
      if (this.peeks.delete(userId))
        this.toUser(userId, 'peek_state', { state: 'ended', message: 'Your Predictor pack was closed.' });
      return;
    }
    const st = this.rowToState(r.rows[0]);
    this.peeks.set(userId, st);
    this.toUser(userId, 'peek_state', this.peekPayload(st, `"${st.name}" is coming up - get ready!`));
  }

  peekOnConnect(userId: number, socketId: string) {
    const st = this.peeks.get(userId);
    if (!st) return;
    this.io.to(socketId).emit('peek_state', this.peekPayload(st));
    if (st.status === 'open' && this.phase === 'BETTING' && !this.peekPaused) {
      this.peekSeen.add(userId);
      this.io.to(socketId).emit('peek', { roundId: this.roundId, crashAt: this.crashAt });
    }
  }

  private async endPeek(st: PeekState, reason: string, status = 'ended') {
    this.peeks.delete(st.userId);
    await pool.query(
      `UPDATE user_peeks SET status=$1, ended_reason=$2, ended_at=now(), predictions_left=$3 WHERE id=$4`,
      [status, reason, st.predictionsLeft, st.id]);
    this.toUser(st.userId, 'peek_state', {
      state: 'ended', name: st.name, predictionsLeft: st.predictionsLeft, message: `Predictor pack finished: ${reason}`,
    });
  }

  // start of every betting phase: open scheduled packs whose countdown finished,
  // deliver the number, and count it down (one round = one prediction, bet or not)
  private async peekRoundStart() {
    this.peekSeen.clear();
    if (kigaliDay() !== this.peekDay) await this.loadPeekProfit();
    const now = Date.now();
    for (const st of [...this.peeks.values()]) {
      if (st.status === 'scheduled') {
        if (now < st.opensAt) continue;
        st.status = 'open';
        st.expiresAt = now + cfg.peekMaxMinutes * 60_000;
        await pool.query(`UPDATE user_peeks SET status='open', opened_at=now(), expires_at=$1 WHERE id=$2`, [new Date(st.expiresAt), st.id]);
        this.toUser(st.userId, 'peek_state', this.peekPayload(st, `"${st.name}" is OPEN - ${st.predictionsLeft} predictions left`));
      } else if (st.expiresAt && now >= st.expiresAt) {
        await this.endPeek(st, 'time expired');
        continue;
      }
      if (st.status !== 'open') continue;
      if (this.peekPaused) { this.toUser(st.userId, 'peek', { paused: true }); continue; }  // not consumed
      if (!this.hasSockets(st.userId)) continue;                                             // offline: not consumed

      this.peekSeen.add(st.userId);
      this.toUser(st.userId, 'peek', { roundId: this.roundId, crashAt: this.crashAt });

      st.predictionsLeft--;
      if (st.predictionsLeft <= 0) { await this.endPeek(st, 'all predictions used'); continue; }
      await pool.query('UPDATE user_peeks SET predictions_left=$1 WHERE id=$2', [st.predictionsLeft, st.id]);
      this.toUser(st.userId, 'peek_state', this.peekPayload(st, `${st.predictionsLeft} predictions left`));
    }
  }

    // after a crash/restart: bets from rounds that never finished are refunded (once, via idempotency key)
  private async recoverAbortedRounds() {
    const r = await pool.query(
      `SELECT b.id, b.user_id, b.amount FROM bets b JOIN rounds r ON r.id = b.round_id
       WHERE r.crash_point IS NULL AND b.cashout_mult IS NULL AND b.payout = 0`);
    for (const x of r.rows) {
      const c = await pool.connect();
      try {
        await c.query('BEGIN');
        await applyDelta(c, +x.user_id, +x.amount, 'refund', `bet:${x.id}`, `betrefund:${x.id}`);
        await c.query('COMMIT');
      } catch (e) { await c.query('ROLLBACK'); console.error('refund failed', x.id, e); }
      finally { c.release(); }
    }
    if (r.rowCount) console.log(`Refunded ${r.rowCount} bets from interrupted rounds`);
  }
}