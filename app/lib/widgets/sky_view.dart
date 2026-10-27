import 'dart:math';
import 'package:flutter/material.dart';
import '../services/game_service.dart';
import '../services/format.dart';

const _ln10 = 2.302585092994046;

Color multColor(double m) =>
    m < 2 ? const Color(0xFF34B4FF) : (m < 10 ? const Color(0xFF913EF8) : const Color(0xFFC017B4));

class SkyView extends StatelessWidget {
  final GameService g;
  final Listenable frame;
  const SkyView({super.key, required this.g, required this.frame});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AnimatedBuilder(
        animation: frame,
        builder: (context, _) {
          g.advanceBg();
          final m = g.liveMult;
          final crashed = g.phase == 'CRASHED';
          final betting = g.phase == 'BETTING';
          final since = g.crashTime == null ? 99.0 : DateTime.now().difference(g.crashTime!).inMilliseconds / 1000.0;
          return Stack(children: [
            Positioned.fill(
              child: CustomPaint(painter: SkyPainter(phase: g.phase, m: m, t: g.clock, bg: g.bgPhase, sinceCrash: since)),
            ),
            if (!betting) Center(child: _multText(m, crashed)),
            if (betting) Center(child: _countdown(g)),
            if (betting) Positioned(left: 0, right: 0, bottom: 0, child: _waitBar(g)),
            if (g.peekState == 'open' && (g.peekNext != null || g.peekPaused))
              Positioned(right: 12, bottom: 16, child: _peekBadge(g)),
            Positioned(left: 12, top: 12, child: PeekBanner(g: g)),
          ]);
        },
      ),
    );
  }

  Widget _multText(double m, bool crashed) {
    const red = Color(0xFFFF3B5C);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (crashed)
        const Text('FLEW AWAY!', style: TextStyle(color: red, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 3)),
      Text('${m.toStringAsFixed(2)}x',
          style: TextStyle(
            fontSize: 72, fontWeight: FontWeight.w900, color: crashed ? red : Colors.white,
            shadows: [Shadow(color: (crashed ? red : multColor(m)).withOpacity(.85), blurRadius: 30)],
          )),
    ]);
  }

  Widget _countdown(GameService g) {
    final left = g.bettingLeftMs;
    final total = g.bettingTotalMs;
    final secs = (left / 1000).ceil();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('NEXT ROUND STARTS IN',
          style: TextStyle(letterSpacing: 3, fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
      const SizedBox(height: 14),
      SizedBox(
        width: 124, height: 124,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: total == 0 ? 0 : left / total, strokeWidth: 8, backgroundColor: Colors.white12,
              color: secs <= 3 ? const Color(0xFFFF3B5C) : const Color(0xFFE5173F),
            ),
          ),
          Text('$secs', style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: Colors.white)),
        ]),
      ),
      const SizedBox(height: 14),
      const Text('Place your bet now', style: TextStyle(color: Colors.white60)),
    ]);
  }

  Widget _waitBar(GameService g) {
    final f = g.bettingTotalMs == 0 ? 0.0 : (g.bettingLeftMs / g.bettingTotalMs).clamp(0.0, 1.0).toDouble();
    return Container(
      height: 6, alignment: Alignment.centerLeft, color: Colors.white10,
      child: FractionallySizedBox(
        widthFactor: f, heightFactor: 1,
        child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFE5173F), Color(0xFFFF6A3D)]))),
      ),
    );
  }

  Widget _peekBadge(GameService g) {
    final x = g.peekNext;
    const purple = Color(0xFFB388FF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.72), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: purple),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(x == null ? 'PEEK PAUSED' : 'YOUR PEEK - THIS ROUND CRASHES AT',
            style: const TextStyle(fontSize: 10, color: purple, letterSpacing: 1.2)),
        if (x != null) ...[
          Text('${x.toStringAsFixed(2)}x', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: purple)),
          Text(
            x < 1.5 ? 'Low round - consider skipping'
                : (x > g.peekMaxMult ? 'Your win is capped at ${g.peekMaxMult.toStringAsFixed(0)}x'
                    : 'Set auto cash-out just below this'),
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
        ],
      ]),
    );
  }
}

class SkyPainter extends CustomPainter {
  final String phase;
  final double m, t, bg, sinceCrash;
  SkyPainter({required this.phase, required this.m, required this.t, required this.bg, required this.sinceCrash});

  @override
  void paint(Canvas c, Size s) {
    final W = s.width, H = s.height;
    final running = phase == 'RUNNING';
    final crashed = phase == 'CRASHED';
    _bg(c, s, running);

    final u = (log(m) / _ln10).clamp(0.0, 1.0).toDouble();
    Offset pt(double uu) => Offset(W * 0.07 + uu * W * 0.72, H * 0.86 - pow(uu, 1.7) * H * 0.60);

    if (running || crashed) {
      final path = Path()..moveTo(pt(0).dx, pt(0).dy);
      const n = 60;
      for (int i = 1; i <= n; i++) {
        final p = pt(u * i / n);
        path.lineTo(p.dx, p.dy);
      }
      final tip0 = pt(u);
      final fill = Path.from(path)..lineTo(tip0.dx, H * 0.86)..lineTo(pt(0).dx, H * 0.86)..close();
      c.drawPath(
        fill,
        Paint()..shader = const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0x66E5173F), Color(0x05E5173F)],
        ).createShader(Rect.fromLTWH(0, 0, W, H)),
      );
      c.drawPath(path, Paint()
        ..color = const Color(0xFFE5173F).withOpacity(.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      c.drawPath(path, Paint()
        ..color = crashed ? Colors.grey : const Color(0xFFFF2D55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4);
    }

    // plane position + tilt
    final sc = (W / 700).clamp(0.6, 1.1).toDouble();
    var tip = pt(u);
    if (phase == 'BETTING') tip += Offset(0, sin(t * 2) * 3);
    if (running && u >= 1) tip += Offset(0, sin(t * 3) * H * 0.015);
    final p1 = pt(max(0.0, u - 0.03));
    final p2 = pt(u);
    final ang = atan2(p2.dy - p1.dy, p2.dx - p1.dx).clamp(-0.85, 0.0).toDouble();
    var op = 1.0;
    if (crashed) {
      final k = (sinceCrash / 0.9).clamp(0.0, 1.0).toDouble();
      tip += Offset(W * 0.55 * k * k, -H * 0.55 * k);   // flies away
      op = 1 - k;
    }
    if (running) {
      for (int k = 1; k <= 5; k++) {
        final d = (50 + k * 16) * sc;
        c.drawCircle(Offset(tip.dx - cos(ang) * d, tip.dy - sin(ang) * d), (3 + k * 1.5) * sc,
            Paint()..color = Colors.white.withOpacity(0.18 - k * 0.028));
      }
    }
    if (op > 0.01) _plane(c, tip, ang, sc, bg * 40, op);
  }

  void _bg(Canvas c, Size s, bool running) {
    final W = s.width, H = s.height;
    final rect = Offset.zero & s;
    c.drawRect(
      rect,
      Paint()..shader = const RadialGradient(
        center: Alignment(0, 0.1), radius: 1.0,
        colors: [Color(0xFF3A1370), Color(0xFF150827), Color(0xFF07030D)], stops: [0, 0.55, 1],
      ).createShader(rect),
    );
    // rotating sun rays
    final ctr = Offset(W * 0.5, H * 0.62);
    final rot = bg * 0.18;
    final R = W + H;
    const rays = 20;
    final rp = Paint()..color = Colors.white.withOpacity(running ? 0.05 : 0.03);
    for (int i = 0; i < rays; i += 2) {
      final a0 = rot + i * 2 * pi / rays, a1 = rot + (i + 1) * 2 * pi / rays;
      c.drawPath(
        Path()
          ..moveTo(ctr.dx, ctr.dy)
          ..lineTo(ctr.dx + R * cos(a0), ctr.dy + R * sin(a0))
          ..lineTo(ctr.dx + R * cos(a1), ctr.dy + R * sin(a1))
          ..close(),
        rp,
      );
    }
    // twinkling stars drifting left
    final rnd = Random(7);
    for (int i = 0; i < 45; i++) {
      final x0 = rnd.nextDouble() * W, y = rnd.nextDouble() * H * 0.85, r = rnd.nextDouble() * 1.6 + 0.4;
      final x = (x0 - bg * 60 * (0.4 + r / 2)) % W;
      final tw = 0.35 + 0.65 * sin(t * 2 + i).abs();
      c.drawCircle(Offset(x, y), r, Paint()..color = Colors.white.withOpacity(0.5 * tw));
    }
    // soft clouds
    final cp = Paint()
      ..color = Colors.white.withOpacity(0.045)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    for (int i = 0; i < 4; i++) {
      final cx = (W * (0.2 + i * 0.3) - bg * 50 * (1 + i * 0.4)) % (W + 300) - 150;
      c.drawOval(Rect.fromCenter(center: Offset(cx, H * (0.25 + (i % 2) * 0.35)), width: 220, height: 46), cp);
    }
    // ground glow
    final g = Rect.fromLTWH(0, H * 0.84, W, H * 0.16);
    c.drawRect(
      g,
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0x00E5173F), Color(0x30E5173F)],
      ).createShader(g),
    );
  }

  void _plane(Canvas c, Offset o, double ang, double sc, double spin, double op) {
    Paint p(Color col) => Paint()..color = col.withOpacity((col.opacity * op).clamp(0.0, 1.0).toDouble());
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(ang);
    c.scale(sc);
    // tail fin
    c.drawPath(Path()..moveTo(-44, -4)..lineTo(-62, -28)..lineTo(-36, -28)..lineTo(-26, -6)..close(), p(const Color(0xFFB5102F)));
    // body
    final body = Path()
      ..moveTo(-48, -6)
      ..quadraticBezierTo(-12, -16, 30, -10)
      ..quadraticBezierTo(52, -5, 52, 0)
      ..quadraticBezierTo(52, 5, 30, 10)
      ..quadraticBezierTo(-12, 16, -48, 6)
      ..close();
    c.drawPath(body, p(const Color(0xFFE5173F)));
    c.drawPath(Path()..moveTo(-40, 3)..quadraticBezierTo(0, 12, 40, 5)..quadraticBezierTo(0, 8, -40, 1)..close(), p(const Color(0x33FFFFFF)));
    // stabilizer + wing
    c.drawPath(Path()..moveTo(-46, 2)..lineTo(-64, 12)..lineTo(-40, 8)..close(), p(const Color(0xFF8E0C24)));
    c.drawPath(Path()..moveTo(-4, 4)..lineTo(-30, 30)..lineTo(-8, 30)..lineTo(20, 5)..close(), p(const Color(0xFFB5102F)));
    // cockpit
    c.drawOval(Rect.fromCenter(center: const Offset(14, -6), width: 22, height: 11), p(const Color(0xFFBFE9FF)));
    // spinning propeller
    final ph = 6 + 26 * sin(spin).abs();
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(55, 0), width: 4, height: ph * 2), const Radius.circular(2)),
        p(const Color(0xCCDDDDDD)));
    c.drawCircle(const Offset(54, 0), 4, p(const Color(0xFF444444)));
    c.restore();
  }

  @override
  bool shouldRepaint(covariant SkyPainter old) => true;
}

class PeekBanner extends StatelessWidget {
  final GameService g;
  const PeekBanner({super.key, required this.g});

  String _mmss(int secs) => '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';

  Widget _box(Color c, List<Widget> kids) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.72), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: kids),
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final kids = <Widget>[];

    if (g.peekState == 'scheduled' && g.peekOpensAt != null) {
      final secs = max(0, g.peekOpensAt!.difference(now).inSeconds);
      kids.add(_box(Colors.amber, [
        Text('PEEK CLASS "${g.peekName.toUpperCase()}" OPENS IN',
            style: const TextStyle(fontSize: 10, color: Colors.amber, letterSpacing: 1.2)),
        Text(secs == 0 ? 'GET READY' : _mmss(secs), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.amber)),
        Text(secs == 0 ? 'Starts with the next round...' : '${g.peekPredictionsLeft} predictions - max win ${g.peekMaxMult.toStringAsFixed(0)}x',
            style: const TextStyle(fontSize: 11, color: Colors.white60)),
      ]));
    } else if (g.peekState == 'open') {
      final left = g.peekExpiresAt == null ? null : max(0, g.peekExpiresAt!.difference(now).inSeconds);
      kids.add(_box(const Color(0xFFB388FF), [
        Text('PEEK OPEN - ${g.peekName.toUpperCase()}',
            style: const TextStyle(fontSize: 10, color: Color(0xFFB388FF), letterSpacing: 1.2)),
        Text('${g.peekPredictionsLeft} predictions left', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text('Max win ${g.peekMaxMult.toStringAsFixed(0)}x${left == null ? '' : ' - ${_mmss(left)} left'}',
            style: const TextStyle(fontSize: 11, color: Colors.white60)),
      ]));
    }

    if (g.peekFlash != null && g.peekFlashUntil != null && now.isBefore(g.peekFlashUntil!)) {
      kids.add(_box(Colors.white54, [Text(g.peekFlash!, style: const TextStyle(fontSize: 12))]));
    }
    if (kids.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: kids));
  }
}