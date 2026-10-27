import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api.dart';
import '../services/game_service.dart';
import '../services/format.dart';

class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key});
  @override
  State<WithdrawScreen> createState() => _WithdrawState();
}

class _WithdrawState extends State<WithdrawScreen> {
  String method = 'momo';
  final dest = TextEditingController();
  final amount = TextEditingController(text: '5000');
  String? err;
  bool busy = false, done = false;

  Future<void> submit() async {
    final g = context.read<GameService>();
    final a = int.tryParse(amount.text) ?? 0;
    var d = dest.text.trim();

    if (a < minWithdraw || a > maxWithdraw) { setState(() => err = 'Amount must be between ${fmt(minWithdraw)} and ${fmt(maxWithdraw)} RWF'); return; }
    if (a > g.balance) { setState(() => err = 'Not enough balance'); return; }
    if (method == 'momo') {
      final digits = d.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 9) { setState(() => err = 'Enter a valid phone number'); return; }
      d = '+250${digits.substring(digits.length - 9)}';
    } else if (!RegExp(r'^T[1-9A-HJ-NP-Za-km-z]{33}$').hasMatch(d)) {
      setState(() => err = 'Enter a valid USDT TRC20 address (starts with T)');
      return;
    }

    setState(() { busy = true; err = null; });
    final r = await Api.withdraw(method, d, a);
    if (!mounted) return;
    if (r['error'] != null) {
      setState(() { busy = false; err = r['error'] == 'INSUFFICIENT_FUNDS' ? 'Not enough balance' : (r['detail'] ?? r['error']).toString(); });
      return;
    }
    g.balance = await Api.balance();
    g.notifyListeners();
    if (mounted) setState(() { busy = false; done = true; });
  }

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(padding: const EdgeInsets.all(18), children: [
            Text('Available: ${fmt(g.balance)} RWF', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'momo', label: Text('MoMo / Airtel'), icon: Icon(Icons.phone_android)),
                ButtonSegment(value: 'crypto', label: Text('Crypto (USDT)'), icon: Icon(Icons.currency_bitcoin)),
              ],
              selected: {method},
              onSelectionChanged: (s) => setState(() { method = s.first; err = null; dest.clear(); }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dest,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: method == 'momo' ? 'Phone number' : 'USDT (TRC20) address',
                prefixText: method == 'momo' ? '+250  ' : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount, keyboardType: TextInputType.number,
              decoration: InputDecoration(
                border: const OutlineInputBorder(), prefixText: 'RWF  ', labelText: 'Amount',
                helperText: 'Min ${fmt(minWithdraw)} - Max ${fmt(maxWithdraw)} RWF per request',
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: busy ? null : submit,
                child: busy ? const CircularProgressIndicator() : const Text('REQUEST WITHDRAWAL'),
              ),
            ),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: Colors.redAccent))),
            if (done)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Card(child: ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.green),
                  title: Text('Withdrawal request received'),
                  subtitle: Text('It will be reviewed before payout.'),
                )),
              ),
          ]),
        ),
      ),
    );
  }
}