import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../domain/notation/parsers/notation_replay.dart';
import '../domain/notation/parsers/parsed_game.dart';
import '../presentation/canju/canju_controller.dart';
import '../presentation/controllers/game_controller.dart';
import '../presentation/game/game_screen.dart';
import '../presentation/home/home_screen.dart';
import '../presentation/library/notation_manager_widget.dart'
    show NotationManagerScreen;
import '../presentation/settings/settings_screen.dart';

/// 全局导航 key：供无 BuildContext 的层（如控制器）弹出权重引导等对话框。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 应用根。
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: '五星象棋',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const HomeScreen(),
      routes: {
        // 路由参数支持三种形态：
        // - (ParsedGame, ReplayData)：棋谱模式，首页已完成解析与回放校验
        // - ParsedGame：兼容只传棋谱的情况
        // - CanjuSession：残局模式，由首页残局入口构造
        '/play': (ctx) {
          final args = ModalRoute.of(ctx)?.settings.arguments;

          // 残局模式：注入 GameController + CanjuController
          if (args is CanjuSession) {
            return MultiProvider(
              providers: [
                ChangeNotifierProvider<GameController>(
                  create: (_) => GameController(),
                ),
                ChangeNotifierProvider<CanjuController>(
                  create: (c) {
                    final gc = c.read<GameController>();
                    return CanjuController(
                      gameController: gc,
                      library: args.library,
                      store: args.store,
                      initialIndex: args.initialIndex,
                    );
                  },
                ),
              ],
              child: const GameScreen(),
            );
          }

          // 棋谱模式
          ParsedGame? game;
          ReplayData? replay;
          if (args is (ParsedGame, ReplayData)) {
            game = args.$1;
            replay = args.$2;
          } else if (args is ParsedGame) {
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
        // 棋谱管理页面：参数为起始目录（可省略，默认 books 目录）
        '/notation-manager': (ctx) {
          final args = ModalRoute.of(ctx)?.settings.arguments;
          return NotationManagerScreen(
            initialDirectory: args is String ? args : null,
          );
        },
      },
    );
  }
}
