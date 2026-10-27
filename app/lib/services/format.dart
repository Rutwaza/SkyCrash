const minDeposit = 1000, maxDeposit = 5000000;
const minWithdraw = 1000, maxWithdraw = 2000000;
const minBet = 100, maxBet = 500000;

String fmt(num n) => n.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');