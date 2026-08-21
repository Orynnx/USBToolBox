import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:toml/toml.dart';

/// 全局配置持久化管理类 (config.toml)
class AppConfig {
  static const String _fileName = 'config.toml';
  static File? _cachedConfigFile;

  /// 获取 config.toml 文件引用
  static Future<File> getConfigFile() async {
    if (_cachedConfigFile != null) {
      return _cachedConfigFile!;
    }
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$_fileName');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    _cachedConfigFile = file;
    return file;
  }

  /// 读取全量配置字典
  static Future<Map<String, dynamic>> loadAll() async {
    try {
      final file = await getConfigFile();
      if (!await file.exists()) {
        return <String, dynamic>{};
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return <String, dynamic>{};
      }
      final tomlDoc = TomlDocument.parse(content);
      return Map<String, dynamic>.from(tomlDoc.toMap());
    } catch (e) {
      debugPrint('[AppConfig] loadAll error: $e');
      return <String, dynamic>{};
    }
  }

  /// 更新并保存特定分节配置
  static Future<void> updateSection(
    String section,
    Map<String, dynamic> sectionData,
  ) async {
    try {
      final allConfig = await loadAll();
      allConfig[section] = sectionData;

      final file = await getConfigFile();
      final tomlString = TomlDocument.fromMap(allConfig).toString();
      await file.writeAsString(tomlString, flush: true);
      debugPrint('[AppConfig] config.toml updated successfully');
    } catch (e) {
      debugPrint('[AppConfig] updateSection error: $e');
    }
  }
}
