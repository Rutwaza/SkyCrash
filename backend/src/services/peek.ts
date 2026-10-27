import { pool } from '../db/pool';
import { cfg } from '../config';
import { getEngine, notifyUser } from './realtime';
import { tg } from './telegram';

const n = (x: number) => x.toLocaleString('en-US');

export async function approvePeekOrder(order: any, note = '') {
  const cls = await pool.query('SELECT * FROM peek_classes WHERE id=$1', [order.class_id]);
  const c = cls.rows[0];
  await pool.query(
    `INSERT INTO user_peeks(user_id,class_id,predictions_left,max_mult,price_paid,opens_at)
     VALUES($1,$2,$3,$4,$5, now() + make_interval(secs => $6::int))`,
    [order.user_id, c.id, c.predictions, c.max_mult, order.amount, cfg.peekDefaultDelaySec]);
  await pool.query(`UPDATE peek_orders SET status='approved', reviewed_at=now(), note=$2 WHERE id=$1`, [order.id, note]);
  await getEngine()?.peekRefresh(+order.user_id);
  const phone = (await pool.query('SELECT phone FROM users WHERE id=$1', [order.user_id])).rows[0].phone;
  notifyUser(+order.user_id, { text: `Predictor pack "${c.name}" activated!` });
  tg(`SKYCRASH ${phone} - PREDICTOR ORDER APPROVED: ${c.name} (${n(+order.amount)} RWF)`);
}