import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../domain/notation/parsers/notation_replay.dart';
import '../domain/notation/parsers/parsed_game.dart';
import '../presentation/controllers/game_controller.dart';
import '../presentation/game/game_screen.dart';
import '../presentation/home/home_screen.dart';
import '../presentation/settings/settings_screen.dart';

/// 应用根。
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '五星象棋',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const HomeScreen(),
      routes: {
        // 路由参数为 (ParsedGame, ReplayData)：
        // 首页已完成解析与完整回放校验，这里只负责载入到控制器。
        '/play': (ctx) {
          final args = ModalRoute.of(ctx)?.settings.arguments;
          ParsedGame? game;
          ReplayData? replay;
          if (args is (ParsedGame, ReplayData)) {
            game = args.$1;
            replay = args.$2;
          } else if (args is ParsedGame) {
            // 兼容只传 ParsedGame 的情况
            game = args;
          }
          return ChangeNotifierProvider(
            create: (_) {
              final gc = GameController();
              if (game != null) {
                // 防御性兜底：首页理论上已校验通过，这里即使再失败
                // 也不让异常逃逸到框架层导致红屏，改为打开空白对局。
                try {
                  gc.loadParsedGame(game, replay: replay);
                } catch (e) {
                  debugPrint('载入棋谱失败: $e');
                }
              }
              return gc;
            },
            child: const GameScreen(),
          );
        },
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}
