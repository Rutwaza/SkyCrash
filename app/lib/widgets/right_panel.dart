import 'package:flutter/material.dart';
import '../services/game_service.dart';
import '../services/format.dart';

class RightPanel extends StatelessWidget {
  final GameService g;
  const RightPanel({super.key, required this.g});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF141418), borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        const Row(children: [
          Icon(Icons.emoji_events, color: Colors.amber, size: 20),
          SizedBox(width: 8),
          Text('TOP WINS', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        ]),
        const SizedBox(height: 10),
        Expanded(
          child: g.topWins.isEmpty
              ? const Center(child: Text('No wins yet.\nBe the first!', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)))
              : ListView.separated(
                  itemCount: g.topWins.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _WinTile(rank: i + 1, w: g.topWins[i]),
                ),
        ),
        const SizedBox(height: 10),
        _BettorsCard(g: g),
      ]),
    );
  }
}

class _WinTile extends StatelessWidget {
  final int rank;
  final WinCard w;
  const _WinTile({required this.rank, required this.w});

  @override
  Widget build(BuildContext context) {
    final medal = rank == 1 ? Colors.amber : (rank == 2 ? Colors.blueGrey.shade200 : (rank == 3 ? Colors.brown.shade300 : Colors.white24));
    final hue = (w.user.codeUnits.fold<int>(0, (a, b) => a + b) * 37) % 360;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF1D3512).withOpacity(.55),
        border: Border.all(color: rank <= 3 ? medal.withOpacity(.6) : Colors.white10),
      ),
      child: Row(children: [
        CircleAvatar(radius: 14, backgroundColor: medal, child: Text('$rank', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 12))),
        const SizedBox(width: 8),
        CircleAvatar(radius: 16, backgroundColor: HSLColor.fromAHSL(1, hue.toDouble(), .5, .4).toColor(), child: Text(w.user[0])),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(w.user, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Bet ${fmt(w.amount)}  -  ${w.m.toStringAsFixed(2)}x', style: const TextStyle(fontSize: 12, color: Colors.white60)),
          ]),
        ),
        Text('+${fmt(w.payout)}', style: const TextStyle(color: Color(0xFF5CE65C), fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _BettorsCard extends StatelessWidget {
  final GameService g;
  const _BettorsCard({required this.g});

  @override
  Widget build(BuildContext context) {
    final label = g.phase == 'BETTING' ? 'PLAYERS IN NEXT ROUND' : (g.phase == 'RUNNING' ? 'PLAYERS THIS ROUND' : 'LAST ROUND PLAYERS');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1C1C22), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.groups, size: 30, color: Colors.lightBlueAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 10, letterSpacing: 1.2, color: Colors.white54)),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Text('${g.bettors}', key: ValueKey(g.bettors), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('STAKED', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Colors.white54)),
          Text('${fmt(g.totalBet)} RWF', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}