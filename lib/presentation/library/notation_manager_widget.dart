import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/config/config_manager.dart';
import 'notation_merger.dart';
import 'notation_repository.dart';

/// 棋谱管理页面：独立页面形态的棋谱管理控件（可注册路由直接打开）。
class NotationManagerScreen extends StatelessWidget {
  const NotationManagerScreen({super.key, this.initialDirectory});

  /// 起始浏览目录；为空时打开应用数据目录下的默认 books 目录。
  final String? initialDirectory;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('棋谱管理')),
      body: SafeArea(
        child: NotationManagerWidget(initialDirectory: initialDirectory),
      ),
    );
  }
}

/// 棋谱管理控件：浏览应用数据目录 `wuxingxiangqi/books` 下的棋谱文件与
/// 子目录。控件不自带 Scaffold，可直接嵌入浮动窗口或新页面。
///
/// - 点击目录进入子目录；点击棋谱文件解析后打开到打谱页面；
/// - 长按任意条目进入多选模式，可对文件与目录执行移动、改名、删除；
///   移动时弹出目标目录选择器，目标不能是被移动项自身或其子目录，
///   且目标目录必须可写（Android 上必要时引导授权）；
/// - [onExternalRepository] 非空时显示「外部仓库」按钮，走旧版外部
///   目录流程（系统文件选择器）。
/// - [onOpenFile] 非空时点击棋谱文件交给外部处理（如先关闭所在浮动
///   窗口再打开打谱页）；为 null 时控件自行打开打谱页。
class NotationManagerWidget extends StatefulWidget {
  const NotationManagerWidget({
    super.key,
    this.initialDirectory,
    this.onExternalRepository,
    this.onOpenFile,
  });

  /// 起始浏览目录；为空时打开应用数据目录下的默认 books 目录。
  final String? initialDirectory;

  /// 「外部仓库」按钮回调；为 null 时不显示该按钮。
  final VoidCallback? onExternalRepository;

  /// 点击棋谱文件回调（入参为文件绝对路径）；为 null 时控件自行
  /// 打开打谱页。
  final ValueChanged<String>? onOpenFile;

  @override
  State<NotationManagerWidget> createState() => _NotationManagerWidgetState();
}

class _NotationManagerWidgetState extends State<NotationManagerWidget> {
  /// books 根目录（初始化后非空）。
  String? _rootPath;

  /// 当前浏览目录。
  String _currentPath = '';

  /// 当前目录下的条目（目录在前、文件在后，名称升序）。
  List<FileSystemEntity> _entries = [];

  bool _loading = true;
  String? _error;

  /// 是否处于多选模式。
  bool _multiSelect = false;

  /// 多选模式下被选中条目的绝对路径集合。
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 初始化：确保 books 目录存在并进入起始目录。
  Future<void> _bootstrap() async {
    try {
      final dataDir = await ConfigManager.instance.dataDirPath;
      final books = Directory(
          '$dataDir${Platform.pathSeparator}books');
      if (!await books.exists()) {
        await books.create(recursive: true);
      }
      _rootPath = books.path;
      _currentPath = widget.initialDirectory ?? books.path;
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '初始化棋谱目录失败：$e';
      });
    }
  }

  /// 重新列出当前目录内容。
  Future<void> _reload() async {
    if (_rootPath == null) return;
    setState(() => _loading = true);
    try {
      final list = <FileSystemEntity>[];
      await for (final e in Directory(_currentPath).list(followLinks: false)) {
        list.add(e);
      }
      // 目录在前、文件在后，同类型按名称升序（忽略大小写）
      int rank(FileSystemEntity e) => e is Directory ? 0 : 1;
      list.sort((a, b) {
        final r = rank(a) - rank(b);
        if (r != 0) return r;
        return _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取目录失败：$e';
      });
    }
  }

  static String _nameOf(FileSystemEntity e) =>
      e.path.split(Platform.pathSeparator).last;

  /// 顶部工具行展示用的当前路径（books 为根的相对显示）。
  String get _displayPath {
    final root = _rootPath!;
    if (_currentPath == root) return 'books';
    final sep = Platform.pathSeparator;
    final rel = _currentPath.substring(root.length + sep.length);
    return 'books / ${rel.replaceAll(sep, ' / ')}';
  }

  bool get _canGoUp => _rootPath != null && _currentPath != _rootPath;

  // ---------------------------------------------------------------------------
  // 浏览交互
  // ---------------------------------------------------------------------------

  void _goUp() {
    if (!_canGoUp) return;
    setState(() {
      _currentPath = Directory(_currentPath).parent.path;
      _multiSelect = false;
      _selected.clear();
    });
    _reload();
  }

  void _enter(String path) {
    setState(() => _currentPath = path);
    _reload();
  }

  /// 点击文件：仅支持棋谱扩展名，解析后打开到打谱页。
  ///
  /// 控件嵌入浮动窗口时由外部传入 [NotationManagerWidget.onOpenFile]：
  /// 先关闭浮动窗口，再打开打谱页。
  Future<void> _openFile(BuildContext context, String path) async {
    final ext = path.split('.').last.toLowerCase();
    if (!kNotationExtensions.contains(ext)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('不支持的文件类型，仅支持：pgn、xqf、cbf、txt'),
      ));
      return;
    }
    final external = widget.onOpenFile;
    if (external != null) {
      external(path);
      return;
    }
    await openNotationFile(context, path);
  }

  /// 在当前目录下新建子目录：
  /// 1. 先校验当前目录有写权限（Android 上必要时引导授权）；
  /// 2. 弹窗输入目录名，校验名称合法且不与现有条目重名；
  /// 3. 创建成功后刷新列表。
  Future<void> _createDirectory() async {
    // 当前目录必须有写权限（Android 上失败时先引导授权重试）
    final writable = await ensureDirectoryWritable(context, _currentPath);
    if (!writable) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('无法新建目录'),
          content: Text('当前目录没有写入权限：\n$_currentPath'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建目录'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '目录名称',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (input == null || !mounted) return;

    final name = input.trim();
    if (name.isEmpty) return;
    if (name.contains('/') ||
        name.contains('\\') ||
        name == '.' ||
        name == '..') {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('目录名不合法，不能包含路径分隔符')));
      return;
    }
    final dest =
        '$_currentPath${Platform.pathSeparator}$name';
    if (await FileSystemEntity.type(dest) != FileSystemEntityType.notFound) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已存在同名文件或目录')));
      return;
    }
    try {
      await Directory(dest).create();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('创建失败：$e')));
      return;
    }
    await _reload();
  }

  // ---------------------------------------------------------------------------
  // 多选与批量操作
  // ---------------------------------------------------------------------------

  void _startMultiSelect(String path) {
    setState(() {
      _multiSelect = true;
      _selected
        ..clear()
        ..add(path);
    });
  }

  void _exitMultiSelect() {
    if (!_multiSelect && _selected.isEmpty) return;
    setState(() {
      _multiSelect = false;
      _selected.clear();
    });
  }

  void _toggleSelect(String path) {
    setState(() {
      if (!_selected.remove(path)) _selected.add(path);
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selected.length == _entries.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_entries.map((e) => e.path));
      }
    });
  }

  /// 批量移动：弹出目标目录选择器 → 校验目标可写（必要时引导授权）→
  /// 逐项 rename；同名冲突或失败的项收集后统一提示。
  Future<void> _moveSelected() async {
    if (_rootPath == null || _selected.isEmpty) return;
    final sources = _selected.toList();
    final target = await showDialog<String>(
      context: context,
      builder: (_) => _DirectoryPickerDialog(
        rootPath: _rootPath!,
        forbidden: sources,
      ),
    );
    if (target == null || !mounted) return;

    // 目标目录必须有写权限（Android 上必要时引导授权后重试）
    final writable = await ensureDirectoryWritable(context, target);
    if (!writable) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('目标目录不可写'),
          content: Text('没有向目标目录写入的权限：\n$target'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    final sep = Platform.pathSeparator;
    final failed = <String>[];
    var moved = 0;
    for (final src in sources) {
      final name = src.split(sep).last;
      final dest = '$target$sep$name';
      if (src == dest) continue;
      // 兜底校验：不能移动到自身或其子目录中（选择器已限制）
      if (target == src || target.startsWith('$src$sep')) {
        failed.add('$name：不能移动到其自身子目录中');
        continue;
      }
      try {
        if (await FileSystemEntity.type(dest) != FileSystemEntityType.notFound) {
          failed.add('$name：目标目录已存在同名项');
          continue;
        }
        if (await FileSystemEntity.type(src) == FileSystemEntityType.directory) {
          await Directory(src).rename(dest);
        } else {
          await File(src).rename(dest);
        }
        moved++;
      } catch (e) {
        failed.add('$name：移动失败（$e）');
      }
    }
    _exitMultiSelect();
    await _reload();
    if (!mounted) return;
    if (failed.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已移动 $moved 项')));
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('部分移动失败'),
          content: Text(failed.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  /// 改名（仅单个选中项可用）。
  Future<void> _renameSelected() async {
    if (_selected.length != 1) return;
    final src = _selected.single;
    final oldName = src.split(Platform.pathSeparator).last;
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '新名称',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (newName == null || !mounted) return;
    final name = newName.trim();
    if (name.isEmpty || name == oldName) return;
    if (name.contains('/') || name.contains('\\')) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('名称不能包含路径分隔符')));
      return;
    }
    final dest =
        '${Directory(src).parent.path}${Platform.pathSeparator}$name';
    try {
      if (await FileSystemEntity.type(dest) != FileSystemEntityType.notFound) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已存在同名项')));
        return;
      }
      if (await FileSystemEntity.type(src) == FileSystemEntityType.directory) {
        await Directory(src).rename(dest);
      } else {
        await File(src).rename(dest);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('重命名失败：$e')));
      return;
    }
    _exitMultiSelect();
    await _reload();
  }

  /// 批量删除：确认后执行；目录递归删除。
  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text(
          '确定删除选中的 $count 项吗？\n\n'
          '目录将被连同其内部全部内容一起删除，此操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final failed = <String>[];
    for (final p in _selected) {
      try {
        final type = await FileSystemEntity.type(p);
        if (type == FileSystemEntityType.directory) {
          await Directory(p).delete(recursive: true);
        } else if (type == FileSystemEntityType.file) {
          await File(p).delete();
        }
      } catch (e) {
        failed.add('${p.split(Platform.pathSeparator).last}：$e');
      }
    }
    _exitMultiSelect();
    await _reload();
    if (failed.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('部分删除失败'),
          content: Text(failed.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 合谱
  // ---------------------------------------------------------------------------

  /// 合谱：展开选中项中的全部 pgn/xqf 棋谱 → 选项对话框（耗时提示/名称/
  /// 格式/位置）→ 权限与同名确认 → 进度对话框中执行 → 结果汇总。
  Future<void> _mergeSelected() async {
    if (_selected.isEmpty) return;

    // 展开目录、收集可合并文件（可能耗时，先弹个轻量进度）
    final sources =
        await NotationMerger.expandSources(_selected.toList());
    if (!mounted) return;
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('选中内容中没有可合并的 PGN/XQF 棋谱')),
      );
      return;
    }

    final options = await NotationMerger.showOptionsDialog(
      context,
      defaultDir: _currentPath,
      fileCount: sources.length,
    );
    if (options == null || !mounted) return;

    // 目标目录必须可写
    final writable = await ensureDirectoryWritable(context, options.directory);
    if (!writable) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('目标目录不可写'),
          content: Text('没有向目标目录写入的权限：\n${options.directory}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    // 同名确认
    if (await File(options.path).exists()) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('文件已存在'),
          content: Text('「${options.fileName}.${options.ext}」已存在，'
              '是否覆盖？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('覆盖'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    if (!mounted) return;
    final outcome = await showDialog<(NotationMergeResult?, Object?)>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MergeProgressDialog(sources: sources, options: options),
    );
    if (outcome == null || !mounted) return;
    final (result, error) = outcome;
    if (error != null || result == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('合并失败'),
          content: Text('$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    _exitMultiSelect();
    await _reload();
    if (!mounted) return;
    final skipped = result.skipped;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('合谱完成'),
        content: Text(
          '已合并 ${result.mergedCount} 个棋谱：\n'
          '${options.fileName}.${options.ext}\n'
          '${skipped.isEmpty ? '' : '\n以下 ${skipped.length} 个文件被跳过：\n'
              '${skipped.join('\n')}'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_rootPath == null) {
      return Center(
        child: _loading
            ? const CircularProgressIndicator(strokeWidth: 2)
            : Text(_error ?? '初始化失败'),
      );
    }
    return Column(
      children: [
        _buildToolBar(),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
        if (_multiSelect) _buildActionBar(),
      ],
    );
  }

  /// 顶部工具行：普通模式为返回上级 + 路径 + 刷新 + 外部仓库；
  /// 多选模式为退出 + 已选数量 + 全选。
  Widget _buildToolBar() {
    if (_multiSelect) {
      return Row(
        children: [
          IconButton(
            onPressed: _exitMultiSelect,
            icon: const Icon(Icons.close),
            tooltip: '退出多选',
          ),
          Expanded(child: Text('已选择 ${_selected.length} 项')),
          TextButton(
            onPressed: _entries.isEmpty ? null : _toggleSelectAll,
            child: Text(
              _selected.length == _entries.length ? '取消全选' : '全选',
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        IconButton(
          onPressed: _canGoUp ? _goUp : null,
          icon: const Icon(Icons.arrow_upward),
          tooltip: '上一级',
        ),
        Expanded(
          child: Text(
            _displayPath,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5A3A1A),
            ),
          ),
        ),
        IconButton(
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
          tooltip: '刷新',
        ),
        IconButton(
          onPressed: _createDirectory,
          icon: const Icon(Icons.create_new_folder),
          tooltip: '新建目录',
        ),
        if (widget.onExternalRepository != null)
          TextButton.icon(
            onPressed: widget.onExternalRepository,
            icon: const Icon(Icons.collections_bookmark, size: 18),
            label: const Text('外部仓库'),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(
        child: Text('目录为空', style: TextStyle(color: Color(0xFFB0A48A))),
      );
    }
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _buildItem(context, _entries[i]),
    );
  }

  Widget _buildItem(BuildContext context, FileSystemEntity e) {
    final path = e.path;
    final isDir = e is Directory;
    final name = _nameOf(e);
    final ext =
        name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final supported = kNotationExtensions.contains(ext);
    final icon = Icon(
      isDir
          ? Icons.folder
          : (supported ? Icons.description : Icons.insert_drive_file),
      color: isDir
          ? const Color(0xFFC8A24B)
          : (supported ? const Color(0xFF8B6B3D) : const Color(0xFFB0A48A)),
    );
    final subtitle = isDir
        ? const Text('目录', style: TextStyle(fontSize: 12))
        : Text(
            supported ? '棋谱文件（${ext.toUpperCase()}）' : '不支持打开',
            style: const TextStyle(fontSize: 12),
          );

    if (_multiSelect) {
      return CheckboxListTile(
        secondary: icon,
        value: _selected.contains(path),
        onChanged: (_) => _toggleSelect(path),
        title: Text(name, overflow: TextOverflow.ellipsis),
        subtitle: subtitle,
        dense: true,
      );
    }
    return ListTile(
      leading: icon,
      title: Text(name, overflow: TextOverflow.ellipsis),
      subtitle: subtitle,
      dense: true,
      onTap: () {
        if (isDir) {
          _enter(path);
        } else {
          _openFile(context, path);
        }
      },
      onLongPress: () => _startMultiSelect(path),
    );
  }

  /// 多选模式底部操作栏：移动 / 改名（单选时可用）/ 删除。
  Widget _buildActionBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFC9B68C))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: _selected.isNotEmpty ? _moveSelected : null,
                icon: const Icon(Icons.drive_file_move, size: 18),
                label: const Text('移动'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: _selected.length == 1 ? _renameSelected : null,
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('改名'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: _selected.isNotEmpty ? _mergeSelected : null,
                icon: const Icon(Icons.merge, size: 18),
                label: const Text('合谱'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: _selected.isNotEmpty ? _deleteSelected : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('删除'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 移动目标目录选择器：从 books 根开始浏览目录树，选择一个目标目录。
// ---------------------------------------------------------------------------

/// 目标目录选择对话框：从 [rootPath] 开始浏览（仅显示子目录），
/// 返回所选目录的绝对路径（pop 结果）；取消返回 null。
///
/// [forbidden] 为被移动项的绝对路径列表：目标目录不能是其中任意一项
/// 自身或其子目录（否则「移动到此处」按钮禁用并提示原因）。
class _DirectoryPickerDialog extends StatefulWidget {
  const _DirectoryPickerDialog({
    required this.rootPath,
    required this.forbidden,
  });

  final String rootPath;
  final List<String> forbidden;

  @override
  State<_DirectoryPickerDialog> createState() => _DirectoryPickerDialogState();
}

class _DirectoryPickerDialogState extends State<_DirectoryPickerDialog> {
  late String _current = widget.rootPath;
  List<Directory> _dirs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final dirs = <Directory>[];
      await for (final e in Directory(_current).list(followLinks: false)) {
        if (e is Directory) dirs.add(e);
      }
      dirs.sort((a, b) => _nameOf(a)
          .toLowerCase()
          .compareTo(_nameOf(b).toLowerCase()));
      if (!mounted) return;
      setState(() {
        _dirs = dirs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dirs = [];
        _loading = false;
      });
    }
  }

  static String _nameOf(Directory d) =>
      d.path.split(Platform.pathSeparator).last;

  String get _displayPath {
    final root = widget.rootPath;
    if (_current == root) return 'books';
    final sep = Platform.pathSeparator;
    final rel = _current.substring(root.length + sep.length);
    return 'books / ${rel.replaceAll(sep, ' / ')}';
  }

  /// 当前浏览目录是否可作为移动目标。
  bool get _canDropHere {
    final sep = Platform.pathSeparator;
    for (final src in widget.forbidden) {
      if (_current == src) return false;
      if (_current.startsWith('$src$sep')) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _current != widget.rootPath
                      ? () {
                          setState(() =>
                              _current = Directory(_current).parent.path);
                          _reload();
                        }
                      : null,
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: '上一级',
                ),
                const Expanded(
                  child: Text(
                    '选择目标目录',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: '取消',
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '移动到：$_displayPath',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF8B6B4A)),
                ),
              ),
            ),
            const Divider(height: 12),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : _dirs.isEmpty
                      ? const Center(
                          child: Text('该目录下没有子目录',
                              style: TextStyle(color: Color(0xFFB0A48A))),
                        )
                      : ListView.separated(
                          itemCount: _dirs.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) => ListTile(
                            leading: const Icon(Icons.folder,
                                color: Color(0xFFC8A24B)),
                            title: Text(_nameOf(_dirs[i])),
                            dense: true,
                            onTap: () {
                              setState(() => _current = _dirs[i].path);
                              _reload();
                            },
                          ),
                        ),
            ),
            if (!_canDropHere)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '目标目录不能是被移动项自身或其子目录',
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _canDropHere
                        ? () => Navigator.pop(context, _current)
                        : null,
                    child: const Text('移动到此处'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 合谱进度对话框
// ---------------------------------------------------------------------------

/// 合谱执行进度对话框：弹出后自动开始合并，实时显示「已处理 n/total」，
/// 不可中途关闭；结束后 pop 出 (结果, 错误)。
class _MergeProgressDialog extends StatefulWidget {
  const _MergeProgressDialog({
    required this.sources,
    required this.options,
  });

  final List<String> sources;
  final NotationMergeOptions options;

  @override
  State<_MergeProgressDialog> createState() => _MergeProgressDialogState();
}

class _MergeProgressDialogState extends State<_MergeProgressDialog> {
  int _done = 0;
  int get _total => widget.sources.length;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final result = await NotationMerger.merge(
        sources: widget.sources,
        options: widget.options,
        onProgress: (done, total) {
          if (mounted) setState(() => _done = done);
        },
      );
      if (mounted) Navigator.pop(context, (result, null));
    } catch (e) {
      if (mounted) Navigator.pop(context, (null, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(strokeWidth: 2),
              const SizedBox(height: 16),
              const Text(
                '正在合并棋谱，请稍候…',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                '已处理 $_done / $_total',
                style: const TextStyle(fontSize: 13, color: Color(0xFF8B6B4A)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
