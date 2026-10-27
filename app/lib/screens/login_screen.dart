import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api.dart';
import '../services/game_service.dart';
import 'game_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final phone = TextEditingController();
  final pass = TextEditingController();
  bool busy = false, isRegister = false, accepted = false, hide = true;
  String? err;

  // accepts 0788123456 or 788123456 -> +250788123456
  String get fullPhone {
    final d = phone.text.replaceAll(RegExp(r'\D'), '');
    return '+250${d.length >= 9 ? d.substring(d.length - 9) : d}';
  }

  Future<void> submit() async {
    if (isRegister && !accepted) { setState(() => err = 'Confirm you are 18+ and accept the terms'); return; }
    setState(() { busy = true; err = null; });
    final e = await Api.auth(isRegister ? 'register' : 'login', fullPhone, pass.text);
    if (!mounted) return;
    if (e != null) { setState(() { busy = false; err = e; }); return; }
    context.read<GameService>().connect(Api.token!);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const GameScreen()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              color: const Color(0xFF1A1A1E),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SvgPicture.asset('assets/logo.svg', height: 48),
                  const SizedBox(height: 4),
                  Text(isRegister ? 'Create account' : 'Login', style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 18),
                  TextField(
                    controller: phone, keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(prefixText: '+250  ', labelText: 'Phone', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 4),
                  const Align(alignment: Alignment.centerLeft,
                      child: Text('Deposits accepted from Airtel and MTN only', style: TextStyle(fontSize: 11, color: Colors.grey))),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pass, obscureText: hide,
                    decoration: InputDecoration(
                      labelText: 'Password (4-16 characters)', border: const OutlineInputBorder(),
                      suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => hide = !hide)),
                    ),
                  ),
                  if (isRegister)
                    CheckboxListTile(
                      value: accepted, onChanged: (v) => setState(() => accepted = v ?? false),
                      contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('I accept the terms and confirm I am over 18 years old.', style: TextStyle(fontSize: 12)),
                    ),
                  if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Colors.redAccent))),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity, height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF12A634), foregroundColor: Colors.white),
                      onPressed: busy ? null : submit,
                      child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(isRegister ? 'JOIN NOW' : 'LOGIN'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() { isRegister = !isRegister; err = null; }),
                    child: Text(isRegister ? 'Already registered? Login' : "Don't have an account? Join now"),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}