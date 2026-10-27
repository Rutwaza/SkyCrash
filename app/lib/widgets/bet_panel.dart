import 'package:flutter/material.dart';
import '../services/game_service.dart';
import '../services/format.dart';

class BetPanel extends StatefulWidget {
  final GameService g;
  final Listenable frame;
  const BetPanel({super.key, required this.g, required this.frame});
  @override
  State<BetPanel> createState() => _BetPanelState();
}

class _BetPanelState extends State<BetPanel> {
  int amount = 500;
  final auto = TextEditingController();

  void setAmt(int v) => setState(() => amount = v.clamp(minBet, maxBet));

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF141418), borderRadius: BorderRadius.circular(14)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton.filledTonal(onPressed: () => setAmt(amount - 100), icon: const Icon(Icons.remove)),
          SizedBox(width: 120, child: Center(child: Text(fmt(amount), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)))),
          IconButton.filledTonal(onPressed: () => setAmt(amount + 100), icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
          for (final v in [500, 2000, 5000, 10000, 50000])
            OutlinedButton(onPressed: () => setAmt(v), child: Text(fmt(v))),
        ]),
        const SizedBox(height: 8),
        Text('Min ${fmt(minBet)} - Max ${fmt(maxBet)} RWF', style: const TextStyle(fontSize: 11, color: Colors.white38)),
        const SizedBox(height: 10),
        SizedBox(
          width: 220,
          child: TextField(
            controller: auto, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(isDense: true, labelText: 'Auto cash out at (optional)', suffixText: 'x', border: OutlineInputBorder()),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: widget.frame,
          builder: (context, _) {
            final betting = g.phase == 'BETTING';
            final running = g.phase == 'RUNNING';
            final inBet = g.myBetId != null;
            String label;
            Color col;
            VoidCallback? onTap;
            if (running && inBet) {
              label = 'CASH OUT  ${fmt(g.myBetAmount * g.liveMult)} RWF';
              col = const Color(0xFFFF9800);
              onTap = g.cashout;
            } else if (betting && !inBet) {
              label = 'BET  ${fmt(amount)} RWF';
              col = const Color(0xFF28A909);
              onTap = () => g.bet(amount, auto: double.tryParse(auto.text));
            } else if (betting && inBet) {
              label = 'BET PLACED  (${fmt(g.myBetAmount)} RWF)';
              col = Colors.blueGrey;
            } else {
              label = running ? 'WAIT FOR NEXT ROUND' : 'ROUND OVER';
              col = Colors.blueGrey;
            }
            return SizedBox(
              width: double.infinity, height: 58,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: col, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: onTap,
                child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            );
          },
        ),
        if (g.msg.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(g.msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.amberAccent))),
      ]),
    );
  }
}