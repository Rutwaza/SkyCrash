import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

const _rate = 22050;

Uint8List _wav(List<double> s) {
  final n = s.length;
  final b = ByteData(44 + n * 2);
  void str(int o, String t) { for (var i = 0; i < t.length; i++) { b.setUint8(o + i, t.codeUnitAt(i)); } }
  str(0, 'RIFF'); b.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE'); str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little); b.setUint32(24, _rate, Endian.little);
  b.setUint32(28, _rate * 2, Endian.little); b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little); str(36, 'data');
  b.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    b.setInt16(44 + i * 2, (s[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

List<double> _tone(double f, double sec, {double vol = 0.4, double f2 = 0}) {
  final n = (_rate * sec).round();
  return List.generate(n, (i) {
    final t = i / _rate;
    final fr = f2 == 0 ? f : f + (f2 - f) * (i / n);
    final env = min(1.0, i / 150) * (1 - i / n);
    return sin(2 * pi * fr * t) * vol * env;
  });
}

class Sfx {
  bool enabled = true;
  final _engine = AudioPlayer();

  // engine hum: 1s loop, all frequencies are whole cycles -> seamless
  late final _engineB = _wav(List.generate(_rate, (i) {
    final t = i / _rate;
    return 0.22 * sin(2 * pi * 90 * t) + 0.12 * sin(2 * pi * 180 * t) +
        0.07 * sin(2 * pi * 270 * t) + 0.05 * sin(2 * pi * 45 * t);
  }));
  late final _beepB = _wav(_tone(880, 0.1));
  late final _clickB = _wav(_tone(520, 0.05, vol: 0.3));
  late final _winB = _wav([..._tone(988, 0.09), ..._tone(1319, 0.2)]);
  late final _crashB = _wav(() {
    final r = Random(1);
    final n = (_rate * 0.7).round();
    return List.generate(n, (i) {
      final t = i / _rate;
      return (r.nextDouble() * 2 - 1) * exp(-t * 6) * 0.55 + sin(2 * pi * (120 - 90 * t) * t) * exp(-t * 4) * 0.5;
    });
  }());

  Future<void> _once(Uint8List b, {double vol = 1}) async {
    if (!enabled) return;
    try {
      final p = AudioPlayer();
      await p.setVolume(vol);
      p.onPlayerComplete.first.then((_) => p.dispose());
      await p.play(BytesSource(b, mimeType: 'audio/wav'));
    } catch (_) {}
  }

  void beep() => _once(_beepB, vol: 0.6);
  void click() => _once(_clickB);
  void win() => _once(_winB);
  void crash() => _once(_crashB);

  Future<void> startEngine() async {
    if (!enabled) return;
    try {
      await _engine.setReleaseMode(ReleaseMode.loop);
      await _engine.setVolume(0.35);
      await _engine.play(BytesSource(_engineB, mimeType: 'audio/wav'));
    } catch (_) {}
  }

  Future<void> setPitch(double m) async {
    try { await _engine.setPlaybackRate((1 + log(m) / ln10 * 1.2).clamp(1.0, 2.5).toDouble()); } catch (_) {}
  }

  Future<void> stopEngine() async {
    try { await _engine.stop(); } catch (_) {}
  }
}