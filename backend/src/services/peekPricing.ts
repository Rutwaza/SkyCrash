import { cfg } from '../config';

const cache = new Map<number, Float64Array>();
const SAMPLES = 300_000;

// profit (in stakes) of one bet on a round whose crash is known: cash out at crash-0.01, capped
function gains(maxMult: number): Float64Array {
  const key = Math.round(maxMult * 100);
  const hit = cache.get(key);
  if (hit) return hit;
  const g = new Float64Array(SAMPLES);
  const e = 2 ** 52;
  for (let i = 0; i < SAMPLES; i++) {
    let c: number;
    if (Math.random() < 1 / cfg.houseEdgeDivisor) c = 1;
    else { const h = Math.floor(Math.random() * e); c = Math.max(1, Math.floor((100 * e - h) / (e - h)) / 100); }
    g[i] = c >= 1.02 ? Math.min(c - 0.01, maxMult) - 1 : -1;
  }
  cache.set(key, g);
  return g;
}

// expected total profit (in multiples of ONE stake) with optimal play:
// each round: bet (uses a bet) or not bet (burns a skip; with no skips left the class ends)
export function valueMultiple(bets: number, skips: number, maxMult: number): number {
  const g = gains(maxMult);
  const f: number[][] = Array.from({ length: bets + 1 }, () => new Array(skips + 1).fill(0));
  for (let b = 1; b <= bets; b++) {
    for (let s = 0; s <= skips; s++) {
      const cont = s > 0 ? f[b][s - 1] : 0;
      const next = f[b - 1][s];
      let acc = 0;
      for (let i = 0; i < g.length; i++) { const v = g[i] + next; acc += v > cont ? v : cont; }
      f[b][s] = acc / g.length;
    }
  }
  return f[bets][skips];
}

// value is expressed per 1000 RWF of stake, since there's no cap to anchor it to
export function quotePerK(predictions: number, maxMult: number) {
  const v = valueMultiple(predictions, 0, maxMult);   // 0 skips: every round is a prediction
  const gainPerK = v * 1000;
  return {
    valueMultiple: +v.toFixed(2),
    gainPer1000Stake: Math.round(gainPerK),
    suggestedPricePer1000: Math.ceil((gainPerK * cfg.peekMargin) / 500) * 500,
  };
}