import crypto from 'crypto';
import { cfg } from '../config';

export const sha256 = (s: string) => crypto.createHash('sha256').update(s).digest('hex');

/**
 * Provably fair crash point.
 * 1/33 of rounds bust at 1.00x; the rest follow 99/(1-r) shape.
 * Together this gives the house ~3% edge, verifiable by anyone.
 */
export function crashPoint(seed: string, publicSalt: string): number {
  const h = crypto.createHmac('sha256', seed).update(publicSalt).digest('hex');
  const n = parseInt(h.slice(0, 13), 16);   // 52 bits
  const e = 2 ** 52;
  if (n % cfg.houseEdgeDivisor === 0) return 1.0;
  return Math.max(1, Math.floor((100 * e - n) / (e - n)) / 100);
}

// time (ms) at which the multiplier reaches m
export const timeForMult = (m: number) => Math.log(m) / cfg.growth;
export const multAt = (ms: number) => Math.floor(Math.exp(cfg.growth * ms) * 100) / 100;