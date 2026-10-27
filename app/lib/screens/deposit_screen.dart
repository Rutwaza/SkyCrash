import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/api.dart';
import '../services/game_service.dart';
import '../services/format.dart';

class DepositScreen extends StatefulWidget {
  const DepositScreen({super.key});
  @override
  State<DepositScreen> createState() => _DepositState();
}

class _DepositState extends State<DepositScreen> {
  String method = 'crypto'; // 'momo' | 'crypto'
  final amount = TextEditingController(text: '5000');
  Map<String, dynamic>? result;
  String? err;
  bool busy = false;
  Timer? poll;
  int startBalance = 0;

  @override
  void dispose() { poll?.cancel(); super.dispose(); }

  Future<void> start() async {
    final a = int.tryParse(amount.text) ?? 0;
    if (a < minDeposit || a > maxDeposit) {
      setState(() => err = 'Amount must be between ${fmt(minDeposit)} and ${fmt(maxDeposit)} RWF');
      return;
    }
    setState(() { busy = true; err = null; result = null; });
    startBalance = context.read<GameService>().balance;
    final r = await Api.deposit(method, a);
    if (!mounted) return;
    if (r['error'] != null) { setState(() { busy = false; err = r['detail']?.toString() ?? r['error'].toString(); }); return; }
    setState(() { busy = false; result = r; });
    // poll balance until the webhook credits it
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 5), (_) async {
      final b = await Api.balance();
      if (!mounted) return;
      final g = context.read<GameService>();
      if (b != g.balance) {
        g.balance = b; g.notifyListeners();
        if (b > startBalance) { poll?.cancel(); setState(() => result = {'done': true}); }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deposit')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(padding: const EdgeInsets.all(18), children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'momo', label: Text('MoMo / Airtel'), icon: Icon(Icons.phone_android)),
                ButtonSegment(value: 'crypto', label: Text('Crypto (USDT)'), icon: Icon(Icons.currency_bitcoin)),
              ],
              selected: {method},
              onSelectionChanged: (s) => setState(() { method = s.first; result = null; err = null; }),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 8, children: [
              for (final v in [1000, 2000, 5000, 10000, 50000,])
                ActionChip(label: Text('+$v'), onPressed: () => setState(() => amount.text = '$v')),
            ]),
            const SizedBox(height: 12),
            TextField(controller: amount, keyboardType: TextInputType.number,
                decoration: InputDecoration(prefixText: 'RWF  ', border: OutlineInputBorder(), helperText: 'Min ${fmt(minDeposit)} MoMo | 17000 Crypto - Max ${fmt(maxDeposit)} RWF', labelText: 'Amount')),
            const SizedBox(height: 14),
            SizedBox(height: 48, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFE600), foregroundColor: Colors.black),
              onPressed: busy ? null : start,
              child: busy ? const CircularProgressIndicator() : const Text('DEPOSIT'),
            )),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: Colors.redAccent))),
            const SizedBox(height: 16),
            if (result?['done'] == true)
              const Card(child: ListTile(leading: Icon(Icons.check_circle, color: Colors.green), title: Text('Deposit received!')))
            else if (result != null && method == 'momo')
              Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Send ${fmt(int.tryParse(amount.text) ?? 0)} RWF via MTN MoMo or Airtel Money to:', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SelectableText(result!['payTo'] ?? '-', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('Send from your registered number. Reference: ${result!['code']}'),
                const SizedBox(height: 8),
                const Text('Your balance updates automatically after the payment.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ])))
            else if (result != null && method == 'crypto')
              Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
                Text('Send exactly ${result!['payAmount']} USDT (TRC20)', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Container(color: Colors.white, padding: const EdgeInsets.all(8),
                    child: QrImageView(data: result!['address'], size: 190)),
                const SizedBox(height: 10),
                SelectableText(result!['address'], textAlign: TextAlign.center),
                TextButton.icon(
                  icon: const Icon(Icons.copy), label: const Text('Copy address'),
                  onPressed: () => Clipboard.setData(ClipboardData(text: result!['address'])),
                ),
                const Text('Only send USDT on the TRC20 network. Balance updates automatically after confirmation.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]))),
          ]),
        ),
      ),
    );
  }
}