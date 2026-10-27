import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api.dart';
import '../services/game_service.dart';
import '../services/format.dart';
import '../widgets/sky_view.dart';
import '../widgets/bet_panel.dart';
import '../widgets/right_panel.dart';
import 'deposit_screen.dart';
import 'withdraw_screen.dart';
import 'login_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late final AnimationController frame =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() { frame.dispose(); super.dispose(); }

  Widget _history(GameService g) => SizedBox(
        height: 34,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final h in g.history.take(30))
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFF1C1C22), borderRadius: BorderRadius.circular(16)),
              child: Text('${h.toStringAsFixed(2)}x', style: TextStyle(fontWeight: FontWeight.w700, color: multColor(h))),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameService>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E10),
        title: SvgPicture.asset('assets/logo.svg', height: 30),
        actions: [
          IconButton(tooltip: 'Sound', onPressed: g.toggleSound, icon: Icon(g.sfx.enabled ? Icons.volume_up : Icons.volume_off)),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.greenAccent),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DepositScreen())),
            child: const Text('Deposit'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WithdrawScreen())),
            child: const Text('Withdraw'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: Text('${fmt(g.balance)} RWF', style: const TextStyle(fontWeight: FontWeight.w800))),
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              g.disconnect();
              await Api.logout();
              if (context.mounted) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              }
            },
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final sky = SkyView(g: g, frame: frame);
        final bet = BetPanel(g: g, frame: frame);
        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(children: [
                  _history(g),
                  const SizedBox(height: 8),
                  Expanded(child: sky),
                  const SizedBox(height: 10),
                  bet,
                ]),
              ),
              const SizedBox(width: 12),
              SizedBox(width: 340, child: RightPanel(g: g)),
            ]),
          );
        }
        return ListView(padding: const EdgeInsets.all(10), children: [
          _history(g),
          const SizedBox(height: 8),
          SizedBox(height: 300, child: sky),
          const SizedBox(height: 10),
          bet,
          const SizedBox(height: 10),
          SizedBox(height: 420, child: RightPanel(g: g)),
        ]);
      }),
    );
  }
}