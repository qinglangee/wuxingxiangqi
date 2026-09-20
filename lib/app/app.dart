import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../presentation/controllers/game_controller.dart';
import '../presentation/game/game_screen.dart';
import '../presentation/home/home_screen.dart';

/// 应用根。
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '中国象棋',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const HomeScreen(),
      routes: {
        '/play': (_) => ChangeNotifierProvider(
              create: (_) => GameController(),
              child: const GameScreen(),
            ),
      },
    );
  }
}
