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

/// 棋规类型枚举。
enum ChessRule {
  /// 中国规则（默认）
  chinese,

  /// 亚洲规则
  asian,

  /// 天天象棋规则
  tiantian,
}

extension ChessRuleExt on ChessRule {
  String get label => switch (this) {
        ChessRule.chinese => '中国规则',
        ChessRule.asian => '亚洲规则',
        ChessRule.tiantian => '天天象棋规则',
      };

  String get code => switch (this) {
        ChessRule.chinese => 'chinese',
        ChessRule.asian => 'asian',
        ChessRule.tiantian => 'tiantian',
      };

  static ChessRule fromCode(String? code) => switch (code) {
        'asian' => ChessRule.asian,
        'tiantian' => ChessRule.tiantian,
        _ => ChessRule.chinese,
      };
}

/// 引擎相关配置。
class EngineConfig {
  EngineConfig({
    this.executablePath,
    this.evalFilePath,
    this.moveTimeMs = 1500,
    this.depth = 20,
    this.maxDepth,
    this.threads = 1,
    this.hashSizeMb = 128,
    this.multiPv = 2,
    this.rule = ChessRule.chinese,
  });

  // ---- 配置项取值范围（供 UI 滑块与引擎层共用） ----
  static const int kMinThreads = 1;
  static const int kMaxThreads = 32;
  static const int kMinHashMb = 16;
  static const int kMaxHashMb = 1024;
  static const int kMinMoveTimeMs = 300;
  static const int kMaxMoveTimeMs = 30000;
  static const int kMinMultiPv = 1;
  static const int kMaxMultiPv = 5;
  static const int kMinDepth = 1;
  static const int kMaxDepth = 60;

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

  /// 引擎线程数（1-32）。
  int threads;

  /// 哈希表大小（MB，16-1024）。
  int hashSizeMb;

  /// 同时输出的候选变化路数 MultiPV（1-5）。
  int multiPv;

  /// 棋规。
  ChessRule rule;

  factory EngineConfig.fromJson(Map<String, dynamic> json) => EngineConfig(
        executablePath: json['executablePath'] as String?,
        evalFilePath: json['evalFilePath'] as String?,
        moveTimeMs: (json['moveTimeMs'] as num?)?.toInt() ?? 500,
        depth: json['depth'] as int?,
        maxDepth: json['maxDepth'] as int?,
        threads: (json['threads'] as num?)?.toInt() ?? 4,
        hashSizeMb: (json['hashSizeMb'] as num?)?.toInt() ?? 256,
        multiPv: (json['multiPv'] as num?)?.toInt() ?? 3,
        rule: ChessRuleExt.fromCode(json['rule'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'executablePath': executablePath,
        'evalFilePath': evalFilePath,
        'moveTimeMs': moveTimeMs,
        'depth': depth,
        'maxDepth': maxDepth,
        'threads': threads,
        'hashSizeMb': hashSizeMb,
        'multiPv': multiPv,
        'rule': rule.code,
      };

  EngineConfig copyWith({
    String? executablePath,
    String? evalFilePath,
    int? moveTimeMs,
    int? depth,
    int? maxDepth,
    int? threads,
    int? hashSizeMb,
    int? multiPv,
    ChessRule? rule,
  }) =>
      EngineConfig(
        executablePath: executablePath ?? this.executablePath,
        evalFilePath: evalFilePath ?? this.evalFilePath,
        moveTimeMs: moveTimeMs ?? this.moveTimeMs,
        depth: depth ?? this.depth,
        maxDepth: maxDepth ?? this.maxDepth,
        threads: threads ?? this.threads,
        hashSizeMb: hashSizeMb ?? this.hashSizeMb,
        multiPv: multiPv ?? this.multiPv,
        rule: rule ?? this.rule,
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
    this.unifiedButtonLabels = true,
    this.globalShowButtonLabels = true,
    Map<String, ButtonBarConfig>? buttonBars,
  }) : buttonBars = buttonBars ?? <String, ButtonBarConfig>{};

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

  /// 是否统一管理所有按钮工具条的文字显示。
  ///
  /// 为 true 时，所有工具条使用 [globalShowButtonLabels]；
  /// 用户在任一工具条上单独切换文字时会自动置为 false。
  bool unifiedButtonLabels;

  /// 统一管理开启时，所有按钮工具条是否显示文字。
  bool globalShowButtonLabels;

  /// 各按钮工具条（按其 id 索引）的个性化配置：按钮顺序、常驻列表、
  /// 非统一管理时该工具条自身的文字显示开关。
  Map<String, ButtonBarConfig> buttonBars;

  factory UiConfig.fromJson(Map<String, dynamic> json) => UiConfig(
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
        fontColor: (json['fontColor'] as num?)?.toInt() ?? 0xFF2A1810,
        backgroundColor:
            (json['backgroundColor'] as num?)?.toInt() ?? 0xFFF5EDD8,
        boardLineColor:
            (json['boardLineColor'] as num?)?.toInt() ?? 0xFF5C3A20,
        boardBackground:
            (json['boardBackground'] as num?)?.toInt() ?? 0xFFE8C988,
        unifiedButtonLabels: json['unifiedButtonLabels'] as bool? ?? true,
        globalShowButtonLabels:
            json['globalShowButtonLabels'] as bool? ?? true,
        buttonBars: (json['buttonBars'] is Map)
            ? Map<String, dynamic>.from(json['buttonBars'] as Map).map(
                (k, v) => MapEntry(
                  k,
                  ButtonBarConfig.fromJson(Map<String, dynamic>.from(v as Map)),
                ),
              )
            : <String, ButtonBarConfig>{},
      );

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'fontColor': fontColor,
        'backgroundColor': backgroundColor,
        'boardLineColor': boardLineColor,
        'boardBackground': boardBackground,
        'unifiedButtonLabels': unifiedButtonLabels,
        'globalShowButtonLabels': globalShowButtonLabels,
        'buttonBars':
            buttonBars.map((k, v) => MapEntry(k, v.toJson())),
      };

  UiConfig copyWith({
    double? fontSize,
    int? fontColor,
    int? backgroundColor,
    int? boardLineColor,
    int? boardBackground,
    bool? unifiedButtonLabels,
    bool? globalShowButtonLabels,
    Map<String, ButtonBarConfig>? buttonBars,
  }) =>
      UiConfig(
        fontSize: fontSize ?? this.fontSize,
        fontColor: fontColor ?? this.fontColor,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        boardLineColor: boardLineColor ?? this.boardLineColor,
        boardBackground: boardBackground ?? this.boardBackground,
        unifiedButtonLabels:
            unifiedButtonLabels ?? this.unifiedButtonLabels,
        globalShowButtonLabels:
            globalShowButtonLabels ?? this.globalShowButtonLabels,
        buttonBars: buttonBars ?? this.buttonBars,
      );
}

/// 单个按钮工具条（AdjustableButtonBar 实例）的持久化配置。
class ButtonBarConfig {
  ButtonBarConfig({
    this.order = const [],
    this.pinned = const [],
    this.showLabels = true,
    Map<String, bool>? checked,
  }) : checked = checked ?? <String, bool>{};

  /// 按钮 id 的完整排列顺序（含内置按钮）。
  List<String> order;

  /// 常驻按钮 id 列表。
  List<String> pinned;

  /// 非统一管理时，该工具条自身是否显示文字。
  bool showLabels;

  /// 各 check button（按按钮 id）的选中状态。
  ///
  /// 工具条在用户点击 check button 时写入；父组件初始化状态时读取，
  /// 使「红AI / 分析 / 自动下一局」等开关在重启后保持。
  Map<String, bool> checked;

  factory ButtonBarConfig.fromJson(Map<String, dynamic> json) =>
      ButtonBarConfig(
        order: (json['order'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        pinned:
            (json['pinned'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        showLabels: json['showLabels'] as bool? ?? true,
        checked: (json['checked'] is Map)
            ? Map<String, dynamic>.from(json['checked'] as Map).map(
                (k, v) => MapEntry(k.toString(), v as bool? ?? false),
              )
            : <String, bool>{},
      );

  Map<String, dynamic> toJson() => {
        'order': order,
        'pinned': pinned,
        'showLabels': showLabels,
        'checked': checked,
      };
}

/// 棋子 / 棋盘相关配置（后续支持自定义资源）。
class BoardConfig {
  /// 显示类型：代码绘制（默认方式）。
  static const String kTypeClassic = 'classic';

  /// 显示类型：图片。
  static const String kTypeImage = 'image';

  BoardConfig({
    this.boardType = kTypeClassic,
    this.pieceType = kTypeClassic,
    this.pieceStyle = 'classic',
    this.boardStyle = 'classic',
    this.customPiecePath,
    this.customBoardPath,
  });

  /// 棋盘显示类型：[kTypeClassic] 代码绘制；[kTypeImage] 图片，
  /// 此时 [boardStyle] 为 `assets/images/boards/` 下的图片文件名。
  String boardType;

  /// 棋子显示类型：[kTypeClassic] 代码绘制；[kTypeImage] 图片，
  /// 此时 [pieceStyle] 为 `assets/images/pieces/` 下的套系目录名。
  String pieceType;

  /// 棋子样式值：classic 类型下为 'classic'；image 类型下为套系目录名。
  String pieceStyle;

  /// 棋盘样式值：classic 类型下为 'classic'；image 类型下为图片文件名。
  String boardStyle;

  /// 用户自定义棋子资源路径（目录或图片包）。为空表示使用 [pieceStyle]。
  String? customPiecePath;

  /// 用户自定义棋盘背景资源路径。为空表示使用 [boardStyle]。
  String? customBoardPath;

  factory BoardConfig.fromJson(Map<String, dynamic> json) => BoardConfig(
        boardType: json['boardType'] as String? ?? kTypeClassic,
        pieceType: json['pieceType'] as String? ?? kTypeClassic,
        pieceStyle: json['pieceStyle'] as String? ?? 'classic',
        boardStyle: json['boardStyle'] as String? ?? 'classic',
        customPiecePath: json['customPiecePath'] as String?,
        customBoardPath: json['customBoardPath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'boardType': boardType,
        'pieceType': pieceType,
        'pieceStyle': pieceStyle,
        'boardStyle': boardStyle,
        'customPiecePath': customPiecePath,
        'customBoardPath': customBoardPath,
      };

  BoardConfig copyWith({
    String? boardType,
    String? pieceType,
    String? pieceStyle,
    String? boardStyle,
    String? customPiecePath,
    String? customBoardPath,
  }) =>
      BoardConfig(
        boardType: boardType ?? this.boardType,
        pieceType: pieceType ?? this.pieceType,
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
