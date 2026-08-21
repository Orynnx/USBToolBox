import 'package:flutter/services.dart';

class DirectorySelection {
  const DirectorySelection(this.uri, this.path);
  final String uri;
  final String path;
}

class DocumentSelection {
  const DocumentSelection(this.uri, this.name, this.size);
  final String uri;
  final String name;
  final int size;
}

class DocumentWriteResult {
  const DocumentWriteResult({
    required this.uri,
    required this.path,
    required this.name,
    required this.size,
  });
  final String uri;
  final String path;
  final String name;
  final int size;

  factory DocumentWriteResult.fromMap(Map<String, dynamic> value) =>
      DocumentWriteResult(
        uri: value['uri'] as String,
        path: value['path'] as String,
        name: value['name'] as String,
        size: (value['size'] as num).toInt(),
      );
}

class DocumentPickerService {
  static const _channel = MethodChannel('org.orynnx.hyperusb/documents');

  static Future<DocumentSelection?> pickFile() async {
    final value = await _channel.invokeMapMethod<String, dynamic>('pickFile');
    return value == null
        ? null
        : DocumentSelection(
            value['uri'] as String,
            value['name'] as String,
            (value['size'] as num).toInt(),
          );
  }

  /// Returns a persisted SAF URI. UVC reads the URI through ContentResolver;
  /// it is deliberately not misrepresented as a filesystem path.
  static Future<DocumentSelection?> pickVideo() async {
    final value = await _channel.invokeMapMethod<String, dynamic>('pickVideo');
    return value == null
        ? null
        : DocumentSelection(
            value['uri'] as String,
            value['name'] as String,
            (value['size'] as num).toInt(),
          );
  }

  static Future<DirectorySelection?> pickDirectory() async {
    final value = await _channel.invokeMapMethod<String, dynamic>(
      'pickDirectory',
    );
    return value == null
        ? null
        : DirectorySelection(value['uri'] as String, value['path'] as String);
  }

  static Future<DocumentWriteResult> createSparse(
    DirectorySelection directory,
    String name,
    int size,
  ) async {
    final value = await _channel
        .invokeMapMethod<String, dynamic>('createSparse', {
          'treeUri': directory.uri,
          'directoryPath': directory.path,
          'name': name,
          'size': size,
        });
    if (value == null) throw PlatformException(code: 'empty_result');
    return DocumentWriteResult.fromMap(value);
  }

  static Future<DocumentWriteResult> copyDocument(
    DocumentSelection source,
    DirectorySelection directory,
  ) async {
    final value = await _channel
        .invokeMapMethod<String, dynamic>('copyDocument', {
          'sourceUri': source.uri,
          'treeUri': directory.uri,
          'directoryPath': directory.path,
        });
    if (value == null) throw PlatformException(code: 'empty_result');
    return DocumentWriteResult.fromMap(value);
  }

  static Future<void> deleteDocument(String uri) =>
      _channel.invokeMethod<void>('deleteDocument', {'uri': uri});
}
