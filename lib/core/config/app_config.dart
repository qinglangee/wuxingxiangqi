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
    this.showScaleStar = true,
    this.showMenuStar = true,
    this.showTabStar = true,
    this.validateNotationOnLoad = true,
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

  /// 是否显示黄色缩放星（棋盘下边缘，拖动调整棋盘大小）。
  bool showScaleStar;

  /// 是否显示红色菜单星（打谱页，环形功能按钮菜单）。
  bool showMenuStar;

  /// 是否显示绿色标签星（打谱页，切换三个标签的显隐）。
  bool showTabStar;

  /// 加载棋谱时是否先完整回放验证（回合结构、着法合法性等）。
  ///
  /// true（默认）：打开前逐着校验，任一步有误即拒绝打开并提示；
  /// false：不做事前验证，直接按棋谱正确进行加载，使用过程中出错
  /// 时再报错。
  bool validateNotationOnLoad;

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
        showScaleStar: json['showScaleStar'] as bool? ?? true,
        showMenuStar: json['showMenuStar'] as bool? ?? true,
        showTabStar: json['showTabStar'] as bool? ?? true,
        validateNotationOnLoad:
            json['validateNotationOnLoad'] as bool? ?? true,
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
        'showScaleStar': showScaleStar,
        'showMenuStar': showMenuStar,
        'showTabStar': showTabStar,
        'validateNotationOnLoad': validateNotationOnLoad,
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
    bool? showScaleStar,
    bool? showMenuStar,
    bool? showTabStar,
    bool? validateNotationOnLoad,
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
        showScaleStar: showScaleStar ?? this.showScaleStar,
        showMenuStar: showMenuStar ?? this.showMenuStar,
        showTabStar: showTabStar ?? this.showTabStar,
        validateNotationOnLoad:
            validateNotationOnLoad ?? this.validateNotationOnLoad,
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
    this.starX,
    this.starY,
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

  /// 浮动红星中心位置：在屏幕坐标系中的 x 坐标（相对屏幕左侧，0-1 归一化），
  /// null 表示未设置（首帧居中显示）。
  double? starX;

  /// 浮动红星中心位置：在屏幕坐标系中的 y 坐标（相对屏幕顶部，0-1 归一化），
  /// null 表示未设置（首帧居中显示）。
  double? starY;

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
        starX: (json['starX'] as num?)?.toDouble(),
        starY: (json['starY'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'order': order,
        'pinned': pinned,
        'showLabels': showLabels,
        'checked': checked,
        'starX': starX,
        'starY': starY,
      };
}

/// 棋子 / 棋盘相关配置（后续支持自定义资源）。
class BoardConfig {
  /// 显示类型：代码绘制（默认方式）。
  static const String kTypeClassic = 'classic';

  /// 显示类型：图片。
  static const String kTypeImage = 'image';

  // ---- 棋子大小 / 阴影设置取值范围（供设置页滑块与绘制层共用） ----

  /// 棋子大小缩放最小值（相对默认大小）。
  static const double kMinPieceSizeScale = 0.2;

  /// 棋子大小缩放最大值。
  static const double kMaxPieceSizeScale = 2.0;

  /// 阴影半径倍数最小值（相对棋子半径）。
  static const double kMinShadowRadiusFactor = 0.2;

  /// 阴影半径倍数最大值。
  static const double kMaxShadowRadiusFactor = 2.0;

  /// 阴影偏移倍数最小值（相对棋子半径，负值表示向左/向上）。
  static const double kMinShadowOffsetFactor = -1.0;

  /// 阴影偏移倍数最大值。
  static const double kMaxShadowOffsetFactor = 1.0;

  /// 阴影模糊最小值（像素）。
  static const double kMinShadowBlur = 0.0;

  /// 阴影模糊最大值（像素）。
  static const double kMaxShadowBlur = 20.0;

  /// 棋盘整体缩放最小值（相对可用宽度）。
  static const double kMinBoardScale = 0.5;

  /// 棋盘整体缩放最大值（1.0 = 占满可用宽度）。
  static const double kMaxBoardScale = 1.0;

  BoardConfig({
    this.boardType = kTypeClassic,
    this.pieceType = kTypeClassic,
    this.pieceStyle = 'classic',
    this.boardStyle = 'classic',
    this.customPiecePath,
    this.customBoardPath,
    this.pieceSizeScale = 1.0,
    this.pieceShadow = true,
    this.shadowRadiusFactor = 1.0,
    this.shadowOffsetXFactor = 0.15,
    this.shadowOffsetYFactor = 0.2,
    this.shadowBlur = 4.0,
    this.boardScale = 1.0,
    this.boardHandleEnabled = false,
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

  /// 棋子大小缩放（相对默认大小），1.0 为默认，范围 [kMinPieceSizeScale, kMaxPieceSizeScale]。
  double pieceSizeScale;

  /// 是否绘制棋子阴影。
  bool pieceShadow;

  /// 阴影半径倍数：阴影圆半径 = 棋子半径 × 此值，默认 1.0 即与棋子等大。
  double shadowRadiusFactor;

  /// 阴影水平偏移倍数（相对棋子半径，正值向右、负值向左）。
  double shadowOffsetXFactor;

  /// 阴影垂直偏移倍数（相对棋子半径，正值向下、负值向上）。
  double shadowOffsetYFactor;

  /// 阴影模糊程度（blurRadius，像素）。
  double shadowBlur;

  /// 棋盘整体缩放比例（相对可用宽度），默认 1.0 占满。
  /// 打谱页棋盘上的五角星把手拖动调整，范围 [kMinBoardScale, kMaxBoardScale]。
  double boardScale;

  /// 五角星缩放把手是否启用。默认 false 显示灰色（禁用），此时点击与
  /// 拖动均无效；长按把手可切换启用状态，启用后显示黄色。
  bool boardHandleEnabled;

  /// 读取数值字段并 clamp 到 [min, max]，缺失或非数值时用 [def]。
  static double _clamp(Object? v, double min, double max, double def) {
    final d = (v as num?)?.toDouble() ?? def;
    return d < min ? min : (d > max ? max : d);
  }

  factory BoardConfig.fromJson(Map<String, dynamic> json) => BoardConfig(
        boardType: json['boardType'] as String? ?? kTypeClassic,
        pieceType: json['pieceType'] as String? ?? kTypeClassic,
        pieceStyle: json['pieceStyle'] as String? ?? 'classic',
        boardStyle: json['boardStyle'] as String? ?? 'classic',
        customPiecePath: json['customPiecePath'] as String?,
        customBoardPath: json['customBoardPath'] as String?,
        pieceSizeScale: _clamp(json['pieceSizeScale'], kMinPieceSizeScale,
            kMaxPieceSizeScale, 1.0),
        pieceShadow: json['pieceShadow'] as bool? ?? true,
        shadowRadiusFactor: _clamp(json['shadowRadiusFactor'],
            kMinShadowRadiusFactor, kMaxShadowRadiusFactor, 1.0),
        shadowOffsetXFactor: _clamp(json['shadowOffsetXFactor'],
            kMinShadowOffsetFactor, kMaxShadowOffsetFactor, 0.15),
        shadowOffsetYFactor: _clamp(json['shadowOffsetYFactor'],
            kMinShadowOffsetFactor, kMaxShadowOffsetFactor, 0.2),
        shadowBlur:
            _clamp(json['shadowBlur'], kMinShadowBlur, kMaxShadowBlur, 4.0),
        boardScale:
            _clamp(json['boardScale'], kMinBoardScale, kMaxBoardScale, 1.0),
        boardHandleEnabled: json['boardHandleEnabled'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'boardType': boardType,
        'pieceType': pieceType,
        'pieceStyle': pieceStyle,
        'boardStyle': boardStyle,
        'customPiecePath': customPiecePath,
        'customBoardPath': customBoardPath,
        'pieceSizeScale': pieceSizeScale,
        'pieceShadow': pieceShadow,
        'shadowRadiusFactor': shadowRadiusFactor,
        'shadowOffsetXFactor': shadowOffsetXFactor,
        'shadowOffsetYFactor': shadowOffsetYFactor,
        'shadowBlur': shadowBlur,
        'boardScale': boardScale,
        'boardHandleEnabled': boardHandleEnabled,
      };

  BoardConfig copyWith({
    String? boardType,
    String? pieceType,
    String? pieceStyle,
    String? boardStyle,
    String? customPiecePath,
    String? customBoardPath,
    double? pieceSizeScale,
    bool? pieceShadow,
    double? shadowRadiusFactor,
    double? shadowOffsetXFactor,
    double? shadowOffsetYFactor,
    double? shadowBlur,
    double? boardScale,
    bool? boardHandleEnabled,
  }) =>
      BoardConfig(
        boardType: boardType ?? this.boardType,
        pieceType: pieceType ?? this.pieceType,
        pieceStyle: pieceStyle ?? this.pieceStyle,
        boardStyle: boardStyle ?? this.boardStyle,
        customPiecePath: customPiecePath ?? this.customPiecePath,
        customBoardPath: customBoardPath ?? this.customBoardPath,
        pieceSizeScale: pieceSizeScale ?? this.pieceSizeScale,
        pieceShadow: pieceShadow ?? this.pieceShadow,
        shadowRadiusFactor: shadowRadiusFactor ?? this.shadowRadiusFactor,
        shadowOffsetXFactor: shadowOffsetXFactor ?? this.shadowOffsetXFactor,
        shadowOffsetYFactor: shadowOffsetYFactor ?? this.shadowOffsetYFactor,
        shadowBlur: shadowBlur ?? this.shadowBlur,
        boardScale: boardScale ?? this.boardScale,
        boardHandleEnabled: boardHandleEnabled ?? this.boardHandleEnabled,
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
