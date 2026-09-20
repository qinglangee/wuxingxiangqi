/// 程序配置（顶层），由若干子配置组成。
///
/// 所有子配置都用 JSON 序列化保存到磁盘；启动时由 [ConfigManager] 读取，
/// 修改时由 [ConfigManager] 落盘。新增字段时请保持向后兼容：
/// 使用 `??` 默认值，避免旧文件缺字段时报错。
class AppConfig {
  AppConfig({
    EngineConfig? engine,
    UiConfig? ui,
    BoardConfig? board,
    LibraryConfig? library,
  })  : engine = engine ?? EngineConfig(),
        ui = ui ?? UiConfig(),
        board = board ?? BoardConfig(),
        library = library ?? LibraryConfig();

  /// 引擎相关配置（可执行文件路径、权重、思考参数等）。
  EngineConfig engine;

  /// 界面风格相关配置（字体、颜色等）。
  UiConfig ui;

  /// 棋子 / 棋盘相关配置（后续支持自定义资源）。
  BoardConfig board;

  /// 棋谱仓库相关配置（目录路径等）。
  LibraryConfig library;

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
        engine: json['engine'] is Map
            ? EngineConfig.fromJson(Map<String, dynamic>.from(json['engine']))
            : EngineConfig(),
        ui: json['ui'] is Map
            ? UiConfig.fromJson(Map<String, dynamic>.from(json['ui']))
            : UiConfig(),
        board: json['board'] is Map
            ? BoardConfig.fromJson(Map<String, dynamic>.from(json['board']))
            : BoardConfig(),
        library: json['library'] is Map
            ? LibraryConfig.fromJson(Map<String, dynamic>.from(json['library']))
            : LibraryConfig(),
      );

  Map<String, dynamic> toJson() => {
        'engine': engine.toJson(),
        'ui': ui.toJson(),
        'board': board.toJson(),
        'library': library.toJson(),
      };

  AppConfig copyWith({
    EngineConfig? engine,
    UiConfig? ui,
    BoardConfig? board,
    LibraryConfig? library,
  }) =>
      AppConfig(
        engine: engine ?? this.engine,
        ui: ui ?? this.ui,
        board: board ?? this.board,
        library: library ?? this.library,
      );
}

/// 引擎相关配置。
class EngineConfig {
  EngineConfig({
    this.executablePath,
    this.evalFilePath,
    this.moveTimeMs = 500,
    this.depth,
    this.maxDepth,
    this.threads,
    this.hashSizeMb,
  });

  /// 引擎可执行文件路径（绝对路径）。为空表示使用内置默认引擎。
  String? executablePath;

  /// 权重文件路径（绝对路径）。为空表示使用内置默认权重。
  String? evalFilePath;

  /// 思考时间（毫秒），[ConfigManager.kMaxMoveTimeMs] 范围内有效。
  int moveTimeMs;

  /// 搜索深度限制（null 表示不限制）。
  int? depth;

  /// 最大深度上限（null 表示不限制）。
  int? maxDepth;

  /// 引擎线程数（null 表示引擎默认）。
  int? threads;

  /// 哈希表大小（MB，null 表示引擎默认）。
  int? hashSizeMb;

  factory EngineConfig.fromJson(Map<String, dynamic> json) => EngineConfig(
        executablePath: json['executablePath'] as String?,
        evalFilePath: json['evalFilePath'] as String?,
        moveTimeMs: (json['moveTimeMs'] as num?)?.toInt() ?? 500,
        depth: json['depth'] as int?,
        maxDepth: json['maxDepth'] as int?,
        threads: json['threads'] as int?,
        hashSizeMb: json['hashSizeMb'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'executablePath': executablePath,
        'evalFilePath': evalFilePath,
        'moveTimeMs': moveTimeMs,
        'depth': depth,
        'maxDepth': maxDepth,
        'threads': threads,
        'hashSizeMb': hashSizeMb,
      };

  EngineConfig copyWith({
    String? executablePath,
    String? evalFilePath,
    int? moveTimeMs,
    int? depth,
    int? maxDepth,
    int? threads,
    int? hashSizeMb,
  }) =>
      EngineConfig(
        executablePath: executablePath ?? this.executablePath,
        evalFilePath: evalFilePath ?? this.evalFilePath,
        moveTimeMs: moveTimeMs ?? this.moveTimeMs,
        depth: depth ?? this.depth,
        maxDepth: maxDepth ?? this.maxDepth,
        threads: threads ?? this.threads,
        hashSizeMb: hashSizeMb ?? this.hashSizeMb,
      );
}

/// 界面风格相关配置。
///
/// 颜色以 0xAARRGGBB 整数形式存储，方便序列化。
class UiConfig {
  UiConfig({
    this.fontSize = 14.0,
    this.fontColor = 0xFF2A1810,
    this.backgroundColor = 0xFFF5EDD8,
    this.boardLineColor = 0xFF5C3A20,
    this.boardBackground = 0xFFE8C988,
  });

  /// 全局正文字号。
  double fontSize;

  /// 全局正文颜色。
  int fontColor;

  /// 页面背景色。
  int backgroundColor;

  /// 棋盘网格线颜色。
  int boardLineColor;

  /// 棋盘背景色。
  int boardBackground;

  factory UiConfig.fromJson(Map<String, dynamic> json) => UiConfig(
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
        fontColor: (json['fontColor'] as num?)?.toInt() ?? 0xFF2A1810,
        backgroundColor:
            (json['backgroundColor'] as num?)?.toInt() ?? 0xFFF5EDD8,
        boardLineColor:
            (json['boardLineColor'] as num?)?.toInt() ?? 0xFF5C3A20,
        boardBackground:
            (json['boardBackground'] as num?)?.toInt() ?? 0xFFE8C988,
      );

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'fontColor': fontColor,
        'backgroundColor': backgroundColor,
        'boardLineColor': boardLineColor,
        'boardBackground': boardBackground,
      };

  UiConfig copyWith({
    double? fontSize,
    int? fontColor,
    int? backgroundColor,
    int? boardLineColor,
    int? boardBackground,
  }) =>
      UiConfig(
        fontSize: fontSize ?? this.fontSize,
        fontColor: fontColor ?? this.fontColor,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        boardLineColor: boardLineColor ?? this.boardLineColor,
        boardBackground: boardBackground ?? this.boardBackground,
      );
}

/// 棋子 / 棋盘相关配置（后续支持自定义资源）。
class BoardConfig {
  BoardConfig({
    this.pieceStyle = 'classic',
    this.boardStyle = 'classic',
    this.customPiecePath,
    this.customBoardPath,
  });

  /// 棋子样式名（内置样式）。后续可扩展为路径，指向用户自定义资源。
  String pieceStyle;

  /// 棋盘样式名（内置样式）。
  String boardStyle;

  /// 用户自定义棋子资源路径（目录或图片包）。为空表示使用 [pieceStyle]。
  String? customPiecePath;

  /// 用户自定义棋盘背景资源路径。为空表示使用 [boardStyle]。
  String? customBoardPath;

  factory BoardConfig.fromJson(Map<String, dynamic> json) => BoardConfig(
        pieceStyle: json['pieceStyle'] as String? ?? 'classic',
        boardStyle: json['boardStyle'] as String? ?? 'classic',
        customPiecePath: json['customPiecePath'] as String?,
        customBoardPath: json['customBoardPath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'pieceStyle': pieceStyle,
        'boardStyle': boardStyle,
        'customPiecePath': customPiecePath,
        'customBoardPath': customBoardPath,
      };

  BoardConfig copyWith({
    String? pieceStyle,
    String? boardStyle,
    String? customPiecePath,
    String? customBoardPath,
  }) =>
      BoardConfig(
        pieceStyle: pieceStyle ?? this.pieceStyle,
        boardStyle: boardStyle ?? this.boardStyle,
        customPiecePath: customPiecePath ?? this.customPiecePath,
        customBoardPath: customBoardPath ?? this.customBoardPath,
      );
}

/// 棋谱仓库相关配置。
class LibraryConfig {
  LibraryConfig({this.notationLibraryPath});

  /// 棋谱仓库根目录（绝对路径）。为空表示尚未配置，需要用户先选择。
  String? notationLibraryPath;

  factory LibraryConfig.fromJson(Map<String, dynamic> json) => LibraryConfig(
        notationLibraryPath: json['notationLibraryPath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'notationLibraryPath': notationLibraryPath,
      };

  LibraryConfig copyWith({String? notationLibraryPath}) => LibraryConfig(
        notationLibraryPath: notationLibraryPath ?? this.notationLibraryPath,
      );
}
