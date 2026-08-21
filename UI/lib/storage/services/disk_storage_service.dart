import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/virtual_disk.dart';

class DiskStorageService {
  static const _key = 'hyperusb.virtual_disks.v1';
  Future<List<VirtualDisk>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((item) => VirtualDisk.fromJson(item as Map<String, dynamic>))
        .toList();
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
