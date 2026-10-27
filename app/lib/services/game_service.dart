import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api.dart';
import 'sounds.dart';

const growth = 0.00006; // must match backend cfg.growth

class WinCard {
  final String user;
  final int amount;
  final double m;
  final int payout;
  WinCard(this.user, this.amount, this.m, this.payout);
}

class GameService extends ChangeNotifier {
  io.Socket? _s;
  final sfx = Sfx();

  String phase = 'BETTING';
  double crashedAt = 1.0;
  List<double> history = [];
  int balance = 0;
  String msg = '';
  String? notice;

  // ---- Predictor pack ----
  String peekState = 'none';        // none | scheduled | open
  String peekName = '';
  int peekPredictionsLeft = 0;
  double peekMaxMult = 10;
  DateTime? peekOpensAt, peekExpiresAt;
  bool peekPaused = false;
  double? peekNext;
  String? peekFlash;
  DateTime? peekFlashUntil;

  void _flash(String t) {
    peekFlash = t;
    peekFlashUntil = DateTime.now().add(const Duration(seconds: 6));
    notice = t;
  }
  int bettors = 0;
  int totalBet = 0;
  List<WinCard> topWins = [];

  int? myBetId;
  int myBetAmount = 0;

  DateTime? bettingEnds;
  int bettingTotalMs = 6000;
  DateTime? runStart;
  DateTime? crashTime;

  // smooth background scroll (speeds up while flying, no jumps on phase change)
  final Stopwatch _sw = Stopwatch()..start();
  double bgPhase = 0;
  int _lastFrameMs = 0;
  double get clock => _sw.elapsedMilliseconds / 1000.0;
  void advanceBg() {
    final now = _sw.elapsedMilliseconds;
    final dt = min(0.1, (now - _lastFrameMs) / 1000.0);
    _lastFrameMs = now;
    bgPhase += dt * (phase == 'RUNNING' ? 1.0 : 0.2);
  }

  Timer? _beepTimer;
  int _lastSec = -1;
  int _tickCount = 0;

  /// client-side prediction so the plane moves at 60fps; the server stays the authority
  double get liveMult {
    if (phase == 'RUNNING' && runStart != null) {
      final ms = DateTime.now().difference(runStart!).inMilliseconds;
      return max(1.0, (exp(growth * ms) * 100).floor() / 100);
    }
    if (phase == 'CRASHED') return crashedAt;
    return 1.0;
  }

  int get bettingLeftMs =>
      bettingEnds == null ? 0 : max(0, bettingEnds!.difference(DateTime.now()).inMilliseconds);

  void connect(String token) {
    _s?.dispose();
    final s = io.io(baseUrl, io.OptionBuilder().setTransports(['websocket']).setAuth({'token': token}).build());
    _s = s;

    s.on('snapshot', (d) {
      phase = d['phase'];
      bettors = (d['bettors'] as num?)?.toInt() ?? 0;
      totalBet = (d['totalBet'] as num?)?.toInt() ?? 0;
      history = [for (final h in (d['history'] as List? ?? [])) (h as num).toDouble()];
      if (phase == 'BETTING') {
        bettingTotalMs = (d['bettingTotal'] as num).toInt();
        bettingEnds = DateTime.now().add(Duration(milliseconds: (d['bettingLeft'] as num).toInt()));
        _startBeeps();
      }
      if (phase == 'RUNNING') {
        runStart = DateTime.now().subtract(Duration(milliseconds: (d['runningFor'] as num).toInt()));
      }
      if (history.isNotEmpty) crashedAt = history.first;
      notifyListeners();
    });
    
    s.on('balance', (d) {
      if (d['balance'] != null) { balance = (d['balance'] as num).toInt(); sfx.win(); }
      if (d['text'] != null) notice = d['text'];
      notifyListeners();
    });

    s.on('peek_state', (d) {
      final st = d['state'] as String;
      if (st == 'ended') {
        peekState = 'none'; peekNext = null; peekPaused = false; peekOpensAt = null; peekExpiresAt = null;
      } else {
        peekState = st;
        peekName = d['name'] ?? peekName;
        peekPredictionsLeft = (d['predictionsLeft'] as num?)?.toInt() ?? peekPredictionsLeft;
        peekMaxMult = (d['maxMult'] as num?)?.toDouble() ?? peekMaxMult;
        peekPaused = d['paused'] == true;
        peekOpensAt = st == 'scheduled' ? DateTime.now().add(Duration(milliseconds: (d['opensInMs'] as num).toInt())) : null;
        peekExpiresAt = d['expiresInMs'] != null ? DateTime.now().add(Duration(milliseconds: (d['expiresInMs'] as num).toInt())) : null;
      }
      if (d['message'] != null) _flash(d['message']);
      notifyListeners();
    });

    s.on('peek', (d) {
      if (d['paused'] == true) { peekPaused = true; peekNext = null; }
      else { peekPaused = false; peekNext = (d['crashAt'] as num).toDouble(); }
      notifyListeners();
    });

    s.on('phase', (d) {
      phase = d['phase'];
      if (phase == 'BETTING') {
        peekNext = null; peekPaused = false;
        myBetId = null; msg = ''; bettors = 0; totalBet = 0; crashTime = null;
        bettingTotalMs = (d['ms'] as num).toInt();
        bettingEnds = DateTime.now().add(Duration(milliseconds: bettingTotalMs));
        _startBeeps();
      } else if (phase == 'RUNNING') {
        _beepTimer?.cancel();
        runStart = DateTime.now();
        _tickCount = 0;
        sfx.startEngine();
      } else if (phase == 'CRASHED') {
        crashedAt = (d['crashAt'] as num).toDouble();
        crashTime = DateTime.now();
        history.insert(0, crashedAt);
        if (history.length > 30) history.removeLast();
        sfx.stopEngine();
        sfx.crash();
        if (myBetId != null) {
          msg = 'Crashed at ${crashedAt.toStringAsFixed(2)}x - bet lost';
          myBetId = null;
        }
      }
      notifyListeners();
    });

    s.on('tick', (d) {
      final m = (d['m'] as num).toDouble();
      runStart = DateTime.now().subtract(Duration(milliseconds: (log(m) / growth).round()));
      if (++_tickCount % 5 == 0) sfx.setPitch(m);
    });

    s.on('stats', (d) {
      bettors = (d['bettors'] as num).toInt();
      totalBet = (d['totalBet'] as num).toInt();
      notifyListeners();
    });

    s.on('cashed', (d) {
      balance = (d['balance'] as num).toInt();
      msg = 'Cashed out ${d['payout']} RWF @ ${(d['m'] as num).toStringAsFixed(2)}x';
      myBetId = null;
      sfx.win();
      notifyListeners();
    });

    s.on('win', (d) {
      topWins.add(WinCard(d['user'], (d['amount'] as num).toInt(), (d['m'] as num).toDouble(), (d['payout'] as num).toInt()));
      topWins.sort((a, b) => b.payout.compareTo(a.payout));
      if (topWins.length > 8) topWins = topWins.sublist(0, 8);
      notifyListeners();
    });

    Api.balance().then((b) { balance = b; notifyListeners(); }).catchError((_) {});
    Api.topWins().then((l) {
      topWins = [for (final x in l) WinCard(x['user'], (x['amount'] as num).toInt(), (x['m'] as num).toDouble(), (x['payout'] as num).toInt())];
      notifyListeners();
    });
  }

  void _startBeeps() {
    _beepTimer?.cancel();
    _lastSec = -1;
    _beepTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      final sec = (bettingLeftMs / 1000).ceil();
      if (sec > 0 && sec <= 3 && sec != _lastSec) { _lastSec = sec; sfx.beep(); }
    });
  }

  String _err(dynamic e) {
    switch (e) {
      case 'INSUFFICIENT_FUNDS': return 'Not enough balance - deposit first';
      case 'BETTING_CLOSED': return 'Betting closed - wait for the next round';
      case 'BAD_AMOUNT': return 'Bet must be between 100 and 500,000 RWF';
      case 'BAD_AUTO': return 'Auto cash-out must be at least 1.01x';
      case 'ALREADY_BET': return 'You already have a bet this round';
      case 'ROUND_FULL': return 'Round limit reached - try next round';
      case 'TOO_LATE': return 'Too late - it crashed';
      default: return e.toString();
    }
  }

  void bet(int amount, {double? auto}) {
    _s?.emitWithAck('bet', {'amount': amount, 'auto': auto}, ack: (r) {
      if (r['ok'] == true) {
        myBetId = (r['id'] as num).toInt();
        myBetAmount = amount;
        balance = (r['balance'] as num).toInt();
        msg = '';
        sfx.click();
      } else {
        msg = _err(r['error']);
      }
      notifyListeners();
    });
  }

  void cashout() {
    if (myBetId == null) return;
    _s?.emitWithAck('cashout', {'betId': myBetId}, ack: (r) {
      if (r['ok'] != true) { msg = _err(r['error']); notifyListeners(); }
    });
  }

  void toggleSound() {
    sfx.enabled = !sfx.enabled;
    if (!sfx.enabled) sfx.stopEngine();
    notifyListeners();
  }

  void disconnect() {
    _beepTimer?.cancel();
    sfx.stopEngine();
    _s?.dispose();
    _s = null;
  }
}