import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/virtual_disk.dart';

class DiskStorageService {
  static const _key = 'hyperusb.virtual_disks.v1';
  final List<String> loadWarnings = [];

  Future<List<VirtualDisk>> load() async {
    loadWarnings.clear();
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('Expected a list');
      final disks = <VirtualDisk>[];
      for (var index = 0; index < decoded.length; index++) {
        try {
          disks.add(
            VirtualDisk.fromJson(
              Map<String, dynamic>.from(decoded[index] as Map),
            ),
          );
        } catch (error) {
          loadWarnings.add('disk[$index]: $error');
        }
      }
      if (loadWarnings.isNotEmpty) debugPrint(loadWarnings.join('\n'));
      return disks;
    } catch (error) {
      loadWarnings.add('registry: $error');
      debugPrint(loadWarnings.single);
      return [];
    }
  }

  Future<void> save(List<VirtualDisk> disks) async =>
      (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode(disks.map((disk) => disk.toJson()).toList()),
      );
  Future<int> verifyRegularFile(String path) async {
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('Backing path is not a regular file', path);
    }
    return stat.size;
  }
}
