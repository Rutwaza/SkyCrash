import 'dotenv/config';
export const cfg = {
  port: +(process.env.PORT || 4000),
  jwt: process.env.JWT_SECRET!,
  db: process.env.DATABASE_URL!,
  houseEdgeDivisor: 33,      // 1/33 instant bust -> ~3% edge
  minBet: 100,
  maxBet: 500_000,
  maxWinPerBet: 5_000_000,
  maxPayoutPerRound: 20_000_000,
  bettingMs: 6000,
  crashedMs: 3500,
  growth: 0.00006,
  publicUrl: process.env.PUBLIC_URL || '',
  usdRwf: +(process.env.USD_RWF || 1450),
  npKey: process.env.NOWPAYMENTS_API_KEY || '',
  npIpn: process.env.NOWPAYMENTS_IPN_SECRET || '',
  minDeposit: 1000,
  maxDeposit: 5_000_000,
  minWithdraw: 1000,
  maxWithdraw: 2_000_000,
  adminPassword: process.env.ADMIN_PASSWORD || '',
  tgToken: process.env.TELEGRAM_BOT_TOKEN || '',
  tgChat: process.env.TELEGRAM_CHAT_ID || '',
  momoNumber: process.env.MOMO_PAY_NUMBER || '',
  peekDailyBudget: +(process.env.PEEK_DAILY_BUDGET || 5_000_000),
  peekMaxMinutes: 30,          // a class expires this long after opening
  peekDefaultDelaySec: 30,     // countdown shown to the player before the class opens
  peekMargin: 1.5,
};