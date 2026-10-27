import { PoolClient } from 'pg';

export async function applyDelta(
  c: PoolClient, userId: number, delta: number, type: string, ref?: string, idem?: string
): Promise<number> {
  if (idem) {
    const dup = await c.query('SELECT balance_after FROM ledger_entries WHERE idem_key=$1', [idem]);
    if (dup.rowCount) return +dup.rows[0].balance_after;     // already processed
  }
  const r = await c.query(
    `UPDATE wallets SET balance = balance + $1
     WHERE user_id=$2 AND balance + $1 >= 0 RETURNING balance`, [delta, userId]);
  if (!r.rowCount) throw new Error('INSUFFICIENT_FUNDS');
  const bal = +r.rows[0].balance;
  await c.query(
    `INSERT INTO ledger_entries(user_id,type,amount,balance_after,ref,idem_key)
     VALUES($1,$2,$3,$4,$5,$6)`, [userId, type, delta, bal, ref ?? null, idem ?? null]);
  return bal;
}