import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import '../config/app_config.dart';

/// 预设主题色选项
class ThemePreset {
  final String id;
  final String nameKey;
  final Color color;

  const ThemePreset({
    required this.id,
    required this.nameKey,
    required this.color,
  });
}

/// 全局支持的预设主题颜色列表
const List<ThemePreset> appThemePresets = [
  ThemePreset(
    id: 'lavender_blue',
    nameKey: 'themePresetDefault',
    color: Color(0xff596a9e),
  ),
  ThemePreset(
    id: 'ocean_blue',
    nameKey: 'themePresetOcean',
    color: Color(0xff1e6091),
  ),
  ThemePreset(
    id: 'emerald_green',
    nameKey: 'themePresetEmerald',
    color: Color(0xff2d6a4f),
  ),
  ThemePreset(
    id: 'sunset_orange',
    nameKey: 'themePresetSunset',
    color: Color(0xffd97706),
  ),
  ThemePreset(
    id: 'crimson_rose',
    nameKey: 'themePresetRose',
    color: Color(0xffbe185d),
  ),
  ThemePreset(
    id: 'deep_purple',
    nameKey: 'themePresetPurple',
    color: Color(0xff7c3aed),
  ),
  ThemePreset(
    id: 'slate_grey',
    nameKey: 'themePresetSlate',
    color: Color(0xff475569),
  ),
];

/// 无动画页面过渡构建器
class _NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimationPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

/// 全局统一页面路由（支持预测性返回背景遮罩、松手平滑淡出及无动画即时响应）
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({
    required super.builder,
    super.settings,
    super.maintainState = true,
    super.fullscreenDialog = false,
    super.allowSnapshotting = false,
  });

  @override
  Color? get barrierColor => appThemeManager.disableAnimations
      ? null
      : Colors.black.withValues(alpha: 0.32);

  @override
  bool get barrierDismissible => false;

  @override
  Duration get transitionDuration => appThemeManager.disableAnimations
      ? Duration.zero
      : const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => appThemeManager.disableAnimations
      ? Duration.zero
      : const Duration(milliseconds: 300);
}

/// 全局主题管理器（支持持久化到 config.toml）
class AppThemeManager extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = const Color(0xff596a9e);
  String _currentPresetId = 'lavender_blue';
  bool _useDynamicColor = true;
  bool _enablePredictiveBack = true;
  bool _disableAnimations = false;

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  String get currentPresetId => _currentPresetId;
  bool get useDynamicColor => _useDynamicColor;
  bool get enablePredictiveBack => _enablePredictiveBack;
  bool get disableAnimations => _disableAnimations;

  /// 从 config.toml 初始化加载主题配置
  Future<void> loadFromConfig() async {
    try {
      final allConfig = await AppConfig.loadAll();
      final themeConfig = allConfig['theme'] as Map<String, dynamic>?;
      if (themeConfig != null) {
        // 1. 读取主题模式
        final modeStr = themeConfig['mode'] as String?;
        if (modeStr != null) {
          switch (modeStr) {
            case 'light':
              _themeMode = ThemeMode.light;
              break;
            case 'dark':
              _themeMode = ThemeMode.dark;
              break;
            default:
              _themeMode = ThemeMode.system;
          }
        }

        // 2. 读取动态取色开关
        if (themeConfig.containsKey('use_dynamic_color')) {
          _useDynamicColor = themeConfig['use_dynamic_color'] as bool? ?? true;
        }

        // 3. 读取主题种子色
        final colorVal = themeConfig['seed_color'];
        if (colorVal is int) {
          _seedColor = Color(colorVal);
        } else if (colorVal is String) {
          final parsed = int.tryParse(
            colorVal.replaceFirst('#', '').replaceFirst('0x', ''),
            radix: 16,
          );
          if (parsed != null) {
            _seedColor = Color(parsed > 0xffffff ? parsed : parsed | 0xff000000);
          }
        }

        // 4. 读取预设色 ID
        if (themeConfig.containsKey('preset_id')) {
          _currentPresetId = themeConfig['preset_id'] as String? ?? 'lavender_blue';
        }

        // 5. 读取预测性返回手势开关
        if (themeConfig.containsKey('enable_predictive_back')) {
          _enablePredictiveBack =
              themeConfig['enable_predictive_back'] as bool? ?? true;
        }

        // 6. 读取移除所有动画开关
        if (themeConfig.containsKey('disable_animations')) {
          _disableAnimations =
              themeConfig['disable_animations'] as bool? ?? false;
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('[AppThemeManager] loadFromConfig error: $e');
    }
  }

  /// 异步持久化到 config.toml
  void _saveToConfig() {
    String modeStr;
    switch (_themeMode) {
      case ThemeMode.light:
        modeStr = 'light';
        break;
      case ThemeMode.dark:
        modeStr = 'dark';
        break;
      case ThemeMode.system:
        modeStr = 'system';
        break;
    }

    AppConfig.updateSection('theme', {
      'mode': modeStr,
      'use_dynamic_color': _useDynamicColor,
      'seed_color': '0x${_seedColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
      'preset_id': _currentPresetId,
      'enable_predictive_back': _enablePredictiveBack,
      'disable_animations': _disableAnimations,
    });
  }

  /// 切换主题模式（跟随系统、浅色、深色）
  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
      _saveToConfig();
    }
  }

  /// 切换是否使用系统动态取色（Material You）
  void setUseDynamicColor(bool value) {
    if (_useDynamicColor != value) {
      _useDynamicColor = value;
      notifyListeners();
      _saveToConfig();
    }
  }

  /// 切换是否启用预测性返回手势
  void setEnablePredictiveBack(bool value) {
    if (_enablePredictiveBack != value) {
      _enablePredictiveBack = value;
      notifyListeners();
      _saveToConfig();
    }
  }

  /// 切换是否移除所有动画
  void setDisableAnimations(bool value) {
    if (_disableAnimations != value) {
      _disableAnimations = value;
      if (value) {
        _enablePredictiveBack = false;
      }
      notifyListeners();
      _saveToConfig();
    }
  }

  /// 切换主题主色调
  void setSeedColor(Color color, [String? presetId]) {
    _seedColor = color;
    _currentPresetId = presetId ?? '';
    _useDynamicColor = false; // 手动选择配色时自动关闭动态取色
    notifyListeners();
    _saveToConfig();
  }

  PageTransitionsTheme get _pageTransitionsTheme {
    if (_disableAnimations) {
      return const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.windows: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.linux: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.macOS: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.iOS: _NoAnimationPageTransitionsBuilder(),
        },
      );
    }

    return PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _enablePredictiveBack
            ? const PredictiveBackPageTransitionsBuilder()
            : const ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: const ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: const ZoomPageTransitionsBuilder(),
        TargetPlatform.macOS: const ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: const ZoomPageTransitionsBuilder(),
      },
    );
  }

  /// 构建浅色主题
  ThemeData getLightTheme([ColorScheme? dynamicLight]) {
    final ColorScheme colorScheme;
    if (_useDynamicColor && dynamicLight != null) {
      colorScheme = dynamicLight.harmonized();
    } else {
      colorScheme = ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.light,
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      pageTransitionsTheme: _pageTransitionsTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 1,
        indicatorColor: colorScheme.secondaryContainer,
      ),
    );
  }

  /// 构建深色主题
  ThemeData getDarkTheme([ColorScheme? dynamicDark]) {
    final ColorScheme colorScheme;
    if (_useDynamicColor && dynamicDark != null) {
      colorScheme = dynamicDark.harmonized();
    } else {
      colorScheme = ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.dark,
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      pageTransitionsTheme: _pageTransitionsTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 1,
        indicatorColor: colorScheme.secondaryContainer,
      ),
    );
  }
}

/// 全局单例主题管理器
final appThemeManager = AppThemeManager();
