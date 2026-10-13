import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

const _kSupportedExtensions = {
  '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.tif', '.webp', '.heic'
};

/// Scans [path]'s directory for supported images, sorted case-insensitively.
/// Pure and self-contained so it can run in a background isolate.
List<String> _scanDirectory(String path) {
  final directory = File(path).parent;
  final images = <String>[];
  try {
    for (final entity in directory.listSync()) {
      if (entity is File) {
        final name = entity.path.toLowerCase();
        final dot = name.lastIndexOf('.');
        if (dot != -1 && _kSupportedExtensions.contains(name.substring(dot))) {
          images.add(entity.path);
        }
      }
    }
    images.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  } catch (_) {
    images.add(path);
  }
  return images;
}

/// Initializes macos_window_utils and styles the window to match the
/// modern (Big Sur+) macOS look with a unified, translucent toolbar.
Future<void> _configureMacosWindow() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = MacosWindowUtilsConfig(
    toolbarStyle: NSWindowToolbarStyle.unified,
  );
  await config.apply();
}

void main() async {
  await _configureMacosWindow();
  runApp(const PhotoViewerApp());
}

class PhotoViewerApp extends StatelessWidget {
  const PhotoViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title: 'Photo Viewer',
      theme: MacosThemeData.light(),
      darkTheme: MacosThemeData.dark(),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const PhotoViewerPage(),
    );
  }
}

class RotateLeftIntent extends Intent {
  const RotateLeftIntent();
}

class RotateRightIntent extends Intent {
  const RotateRightIntent();
}

class PreviousImageIntent extends Intent {
  const PreviousImageIntent();
}

class NextImageIntent extends Intent {
  const NextImageIntent();
}

class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({super.key});

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  static const _channel = MethodChannel('com.example.basic_photo_viewer/file');
  static const _supportedExtensions = _kSupportedExtensions;

  String? _filePath;
  List<String> _imageFiles = [];
  int _currentIndex = 0;
  double _scale = 1.0;
  double _rotation = 0.0;
  bool _hasError = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleMethodCall);
    // Tell native the handler is registered so it can deliver any file that
    // was opened (e.g. via Finder double-click) before Dart finished starting.
    _channel.invokeMethod('ready');
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'openFile') {
      final args = call.arguments;
      if (args is Map) {
        // New format from native: {files: [...], currentIndex: n}
        final files = (args['files'] as List).cast<String>();
        final currentIndex = args['currentIndex'] as int;
        _openFiles(files, currentIndex);
      } else if (args is String) {
        // Fallback for simple path (e.g., from drag & drop)
        _openFile(args);
      }
    } else if (call.method == 'setImageList') {
      // Background folder scan finished: backfill navigation without
      // disturbing the image currently on screen.
      final args = call.arguments as Map;
      final files = (args['files'] as List).cast<String>();
      _setImageList(files);
    }
  }

  void _openFiles(List<String> files, int currentIndex) {
    if (files.isEmpty) return;

    setState(() {
      _imageFiles = files;
      _currentIndex = currentIndex.clamp(0, files.length - 1);
      _filePath = files[_currentIndex];
      _scale = 1.0;
      _rotation = 0.0;
      _hasError = false;
    });
  }

  /// Backfills the navigation list after a background scan. The displayed file
  /// is the source of truth: re-locate it in [files] rather than trusting any
  /// index, and leave the image, zoom, and rotation untouched.
  void _setImageList(List<String> files) {
    if (_filePath == null) return; // nothing displayed yet
    final idx = files.indexOf(_filePath!);
    if (idx < 0) return; // stale (newer open) or filtered out: keep current state
    setState(() {
      _imageFiles = files;
      _currentIndex = idx;
    });
  }

  Future<void> _openFile(String path) async {
    // Phase 1: render the dropped image immediately.
    _openFiles([path], 0);
    // Phase 2: scan its folder off the UI isolate, then backfill navigation.
    final images = await Isolate.run(() => _scanDirectory(path));
    if (!mounted) return;
    _setImageList(images);
  }

  void _navigateToIndex(int index) {
    if (_imageFiles.isEmpty) return;
    if (index < 0 || index >= _imageFiles.length) return;

    setState(() {
      _currentIndex = index;
      _filePath = _imageFiles[index];
      _scale = 1.0;
      _rotation = 0.0;
      _hasError = false;
    });
  }

  void _previousImage() {
    if (_imageFiles.isEmpty) return;
    final newIndex = _currentIndex > 0 ? _currentIndex - 1 : _imageFiles.length - 1;
    _navigateToIndex(newIndex);
  }

  void _nextImage() {
    if (_imageFiles.isEmpty) return;
    final newIndex = _currentIndex < _imageFiles.length - 1 ? _currentIndex + 1 : 0;
    _navigateToIndex(newIndex);
  }

  void _handleDrop(DropDoneDetails details) {
    final files = details.files;
    if (files.isEmpty) return;

    // Find the first supported image file
    for (final file in files) {
      final ext = file.name.toLowerCase();
      final dotIndex = ext.lastIndexOf('.');
      if (dotIndex != -1) {
        final extension = ext.substring(dotIndex);
        if (_supportedExtensions.contains(extension)) {
          _openFile(file.path);
          return;
        }
      }
    }
  }

  void _rotateLeft() {
    setState(() {
      _rotation -= pi / 4;
    });
  }

  void _rotateRight() {
    setState(() {
      _rotation += pi / 4;
    });
  }

  void _zoomIn() {
    setState(() {
      _scale = (_scale * 1.2).clamp(0.1, 10.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _scale = (_scale / 1.2).clamp(0.1, 10.0);
    });
  }

  void _reset() {
    setState(() {
      _scale = 1.0;
      _rotation = 0.0;
    });
  }

  void _handleScroll(PointerScrollEvent event) {
    setState(() {
      if (event.scrollDelta.dy < 0) {
        _scale = (_scale * 1.1).clamp(0.1, 10.0);
      } else {
        _scale = (_scale / 1.1).clamp(0.1, 10.0);
      }
    });
  }

  String get _filename {
    if (_filePath == null) return 'Photo Viewer';
    return _filePath!.split('/').last;
  }

  String get _title {
    if (_filePath == null) return 'Photo Viewer';
    if (_imageFiles.length > 1) {
      return '${_currentIndex + 1} of ${_imageFiles.length}  ·  $_filename';
    }
    return _filename;
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _filePath != null;
    final canNavigate = _imageFiles.length > 1;

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.arrowLeft):
            const RotateLeftIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.arrowRight):
            const RotateRightIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const PreviousImageIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const NextImageIntent(),
      },
      child: Actions(
        actions: {
          RotateLeftIntent: CallbackAction<RotateLeftIntent>(
            onInvoke: (_) => _rotateLeft(),
          ),
          RotateRightIntent: CallbackAction<RotateRightIntent>(
            onInvoke: (_) => _rotateRight(),
          ),
          PreviousImageIntent: CallbackAction<PreviousImageIntent>(
            onInvoke: (_) => _previousImage(),
          ),
          NextImageIntent: CallbackAction<NextImageIntent>(
            onInvoke: (_) => _nextImage(),
          ),
        },
        child: Focus(
          autofocus: true,
          child: MacosWindow(
            child: MacosScaffold(
              toolBar: ToolBar(
                title: Text(_title),
                titleWidth: 320.0,
                actions: [
                  ToolBarIconButton(
                    label: 'Previous',
                    icon: const MacosIcon(CupertinoIcons.chevron_left),
                    onPressed: canNavigate ? _previousImage : null,
                    showLabel: false,
                    tooltipMessage: 'Previous Image (Left Arrow)',
                  ),
                  ToolBarIconButton(
                    label: 'Next',
                    icon: const MacosIcon(CupertinoIcons.chevron_right),
                    onPressed: canNavigate ? _nextImage : null,
                    showLabel: false,
                    tooltipMessage: 'Next Image (Right Arrow)',
                  ),
                  const ToolBarSpacer(),
                  ToolBarIconButton(
                    label: 'Rotate Left',
                    icon: const MacosIcon(CupertinoIcons.rotate_left),
                    onPressed: hasImage ? _rotateLeft : null,
                    showLabel: false,
                    tooltipMessage: 'Rotate Left (Cmd+Left)',
                  ),
                  ToolBarIconButton(
                    label: 'Rotate Right',
                    icon: const MacosIcon(CupertinoIcons.rotate_right),
                    onPressed: hasImage ? _rotateRight : null,
                    showLabel: false,
                    tooltipMessage: 'Rotate Right (Cmd+Right)',
                  ),
                  const ToolBarSpacer(),
                  ToolBarIconButton(
                    label: 'Zoom Out',
                    icon: const MacosIcon(CupertinoIcons.zoom_out),
                    onPressed: hasImage ? _zoomOut : null,
                    showLabel: false,
                    tooltipMessage: 'Zoom Out',
                  ),
                  ToolBarIconButton(
                    label: 'Zoom In',
                    icon: const MacosIcon(CupertinoIcons.zoom_in),
                    onPressed: hasImage ? _zoomIn : null,
                    showLabel: false,
                    tooltipMessage: 'Zoom In',
                  ),
                  ToolBarIconButton(
                    label: 'Reset',
                    icon: const MacosIcon(CupertinoIcons.arrow_counterclockwise),
                    onPressed: hasImage ? _reset : null,
                    showLabel: false,
                    tooltipMessage: 'Reset Zoom & Rotation',
                  ),
                ],
              ),
              children: [
                ContentArea(
                  builder: (context, scrollController) {
                    return DropTarget(
                      onDragEntered: (_) => setState(() => _isDragging = true),
                      onDragExited: (_) => setState(() => _isDragging = false),
                      onDragDone: (details) {
                        setState(() => _isDragging = false);
                        _handleDrop(details);
                      },
                      child: Stack(
                        children: [
                          _buildBody(),
                          if (_isDragging) _buildDropOverlay(),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropOverlay() {
    final theme = MacosTheme.of(context);
    return Container(
      color: theme.primaryColor.withValues(alpha: 0.08),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: theme.canvasColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.primaryColor, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MacosIcon(
                CupertinoIcons.tray_arrow_down,
                size: 48,
                color: theme.primaryColor,
              ),
              const SizedBox(height: 16),
              Text(
                'Drop image here',
                style: theme.typography.title2.copyWith(
                  color: theme.primaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final theme = MacosTheme.of(context);

    if (_filePath == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MacosIcon(
              CupertinoIcons.photo,
              size: 72,
              color: MacosColors.systemGrayColor,
            ),
            const SizedBox(height: 16),
            Text(
              'No Image Open',
              style: theme.typography.title1.copyWith(
                color: MacosColors.systemGrayColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Drop an image here or use “Open With” from Finder',
              style: theme.typography.body.copyWith(
                color: MacosColors.systemGrayColor,
              ),
            ),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MacosIcon(
              CupertinoIcons.exclamationmark_triangle,
              size: 72,
              color: MacosColors.systemRedColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to Load Image',
              style: theme.typography.title1.copyWith(
                color: MacosColors.systemRedColor,
              ),
            ),
          ],
        ),
      );
    }

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _handleScroll(event);
        }
      },
      child: InteractiveViewer(
        minScale: 0.1,
        maxScale: 10.0,
        child: Center(
          child: Transform.rotate(
            angle: _rotation,
            child: Transform.scale(
              scale: _scale,
              child: Image.file(
                File(_filePath!),
                errorBuilder: (context, error, stackTrace) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!_hasError) {
                      setState(() {
                        _hasError = true;
                      });
                    }
                  });
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
