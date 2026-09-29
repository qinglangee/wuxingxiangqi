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
import '../presentation/session/game_session_store.dart';
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
        // 路由参数支持以下形态：
        // - (ParsedGame, ReplayData, String?, List<String>, int)：
        //   棋谱模式，附带会话棋谱列表（同目录棋谱文件）与当前局下标
        // - (ParsedGame, ReplayData, String?)：棋谱模式（无会话列表）
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
              child: GameScreen(),
            );
          }

          // 棋谱模式
          ParsedGame? game;
          ReplayData? replay;
          String? sourcePath;
          List<String>? sessionGames;
          int sessionGameIndex = -1;
          if (args is (ParsedGame, ReplayData, String?, List<String>, int)) {
            game = args.$1;
            replay = args.$2;
            sourcePath = args.$3;
            sessionGames = args.$4;
            sessionGameIndex = args.$5;
          } else if (args is (ParsedGame, ReplayData, String?)) {
            game = args.$1;
            replay = args.$2;
            sourcePath = args.$3;
          } else if (args is (ParsedGame, ReplayData)) {
            game = args.$1;
            replay = args.$2;
          } else if (args is ParsedGame) {
            game = args;
          }
          return ChangeNotifierProvider(
            create: (_) {
              final gc = GameController();
              if (game != null) {
                // 有传入的棋谱：使用新棋局
                try {
                  gc.loadParsedGame(game,
                      replay: replay, sourcePath: sourcePath);
                } catch (e) {
                  debugPrint('载入棋谱失败: $e');
                }
                // 会话棋谱列表：供复盘导航条「上一局/下一局/选谱」切换
                if (sessionGames != null) {
                  gc.setSessionGames(sessionGames, sessionGameIndex);
                }
              } else {
                // 无传入棋谱：异步加载上次保存的会话
                _loadSavedSession(gc);
              }
              return gc;
            },
            child: GameScreen(),
          );
        },
        '/settings': (_) => const SettingsScreen(),
        // 棋谱管理页面：参数为 String 时表示起始目录（默认 books 根）；
        // 参数为 (String root, String? label) 记录时以 root 为浏览根目录
        // （用于外部棋谱仓库）。
        '/notation-manager': (ctx) {
          final args = ModalRoute.of(ctx)?.settings.arguments;
          if (args is (String, String?)) {
            return NotationManagerScreen(
              rootDirectory: args.$1,
              rootLabel: args.$2,
              title: args.$2 != null ? '外部仓库 · ${args.$2}' : '棋谱管理',
            );
          }
          return NotationManagerScreen(
            initialDirectory: args is String ? args : null,
          );
        },
      },
    );
  }
}

/// 异步加载上次保存的会话状态并恢复到 [gc]。
///
/// 无保存或解析失败时静默失败，[gc] 保持标准开局。
void _loadSavedSession(GameController gc) async {
  try {
    final session = await GameSessionStore.load();
    if (session != null) {
      gc.loadParsedGame(session.game, sourcePath: session.sourcePath);
      gc.jumpToPath(session.nodePath);
      // 恢复复盘分析数据
      if (session.analysis != null) {
        gc.reviewAnalysis = session.analysis;
      }
    }
  } catch (e) {
    debugPrint('恢复会话失败: $e');
  }
}
