import crypto from 'crypto';
import { pool } from '../src/db/pool';
import { sha256 } from '../src/services/fair';

(async () => {
  const N = 1_000_000;
  // seed[i+1] = sha256(seed[i]); we PLAY from the highest index downward,
  // so each revealed seed hashes to the previously revealed one: verifiable chain.
  let s = crypto.randomBytes(32).toString('hex');
  const rows: [number, string][] = [[0, s]];
  for (let i = 1; i <= N; i++) { s = sha256(s); rows.push([i, s]); }
  const client = await pool.connect();
  await client.query('TRUNCATE seed_chain');
  for (let i = 0; i < rows.length; i += 5000) {
    const chunk = rows.slice(i, i + 5000);
    const vals = chunk.map((_, k) => `($${k*2+1},$${k*2+2})`).join(',');
    await client.query(`INSERT INTO seed_chain VALUES ${vals}`, chunk.flat());
  }
  console.log('Publish this terminal hash publicly NOW:', rows[N][1]);
  client.release(); process.exit(0);
})();