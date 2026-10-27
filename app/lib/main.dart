import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/api.dart';
import 'services/game_service.dart';
import 'screens/login_screen.dart';
import 'screens/game_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.loadToken();
  final game = GameService();
  if (Api.token != null) game.connect(Api.token!);
  runApp(ChangeNotifierProvider.value(value: game, child: const App()));
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SkyCrash',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xFF0E0E10),
          colorScheme: const ColorScheme.dark(primary: Color(0xFFE5173F)),
        ),
        home: Api.token == null ? const LoginScreen() : const GameScreen(),
      );
}