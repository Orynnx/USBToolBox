import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DirectorySelection {
  const DirectorySelection(this.uri, this.path);
  final String uri;
  final String path;
}

class DocumentSelection {
  const DocumentSelection(this.uri, this.name, this.size, {this.directPath});
  final String uri;
  final String name;
  final int size;
  final String? directPath;
}

class DocumentCopyProgress {
  const DocumentCopyProgress(this.copiedBytes, this.totalBytes);
  final int copiedBytes;
  final int totalBytes;

  double? get fraction =>
      totalBytes > 0 ? (copiedBytes / totalBytes).clamp(0.0, 1.0) : null;
}

class DocumentCopyTask {
  DocumentCopyTask._(this.operationId);

  final String operationId;
  final progress = ValueNotifier<DocumentCopyProgress>(
    const DocumentCopyProgress(0, 0),
  );
  late final Future<DocumentWriteResult> result;
  StreamSubscription<dynamic>? _events;

  Future<void> cancel() => DocumentPickerService.cancelCopy(operationId);

  Future<void> dispose() async {
    await _events?.cancel();
    progress.dispose();
  }
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
  static const _eventChannel = EventChannel(
    'org.orynnx.hyperusb/document_events',
  );
  static final Stream<dynamic> _events = _eventChannel
      .receiveBroadcastStream()
      .asBroadcastStream();
  static int _nextOperation = 0;

  static Future<DocumentSelection?> pickFile() async {
    final value = await _channel.invokeMapMethod<String, dynamic>('pickFile');
    return value == null
        ? null
        : DocumentSelection(
            value['uri'] as String,
            value['name'] as String,
            (value['size'] as num).toInt(),
            directPath: value['directPath'] as String?,
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
            directPath: value['directPath'] as String?,
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

  static DocumentCopyTask copyDocument(
    DocumentSelection source,
    DirectorySelection directory,
  ) {
    final operationId =
        '${DateTime.now().microsecondsSinceEpoch}-${_nextOperation++}';
    final task = DocumentCopyTask._(operationId);
    task._events = _events.listen((dynamic event) {
      if (event is! Map || event['operationId'] != operationId) return;
      task.progress.value = DocumentCopyProgress(
        (event['copiedBytes'] as num?)?.toInt() ?? 0,
        (event['totalBytes'] as num?)?.toInt() ?? 0,
      );
    });
    task.result = _channel
        .invokeMapMethod<String, dynamic>('copyDocument', {
          'sourceUri': source.uri,
          'treeUri': directory.uri,
          'directoryPath': directory.path,
          'operationId': operationId,
        })
        .then((value) {
          if (value == null) throw PlatformException(code: 'empty_result');
          return DocumentWriteResult.fromMap(value);
        })
        .whenComplete(() => task._events?.cancel());
    return task;
  }

  static Future<void> cancelCopy(String operationId) async {
    await _channel.invokeMethod<bool>('cancelCopy', {
      'operationId': operationId,
    });
  }

  static Future<void> deleteDocument(String uri) =>
      _channel.invokeMethod<void>('deleteDocument', {'uri': uri});
}
