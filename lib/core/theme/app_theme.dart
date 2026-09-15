import 'package:flutter/material.dart';

/// 应用主题：棋盘木色 + 黑红棋子色。
class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B5A2B)),
        scaffoldBackgroundColor: const Color(0xFFF5E6C8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF8B5A2B),
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
      );

  // 棋盘配色
  static const Color boardBackground = Color(0xFFE8C882);
  static const Color boardLine = Color(0xFF5A3A1A);
  static const Color riverFill = Color(0xFFD9B977);

  // 棋子配色
  static const Color redPiece = Color(0xFFC62828);
  static const Color blackPiece = Color(0xFF212121);
  static const Color pieceBackground = Color(0xFFF5E6C8);
  static const Color pieceBorder = Color(0xFF8B5A2B);

  // 提示色
  static const Color selectedHighlight = Color(0x6600BFA5);
  static const Color moveHintDot = Color(0xAA00BFA5);
}
