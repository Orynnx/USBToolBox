enum VirtualDiskType { disk, cdrom }

class VirtualDisk {
  const VirtualDisk({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.type,
    required this.readOnly,
    required this.removable,
    required this.enableFua,
    required this.desiredEnabled,
    required this.managedFile,
    required this.sizeBytes,
    this.documentUri,
  });
  final String id, name, imagePath;
  final VirtualDiskType type;
  final bool readOnly, removable, enableFua, desiredEnabled, managedFile;
  final int sizeBytes;
  final String? documentUri;
  VirtualDisk copyWith({
    String? name,
    String? imagePath,
    VirtualDiskType? type,
    bool? readOnly,
    bool? removable,
    bool? enableFua,
    bool? desiredEnabled,
    bool? managedFile,
    int? sizeBytes,
    String? documentUri,
  }) => VirtualDisk(
    id: id,
    name: name ?? this.name,
    imagePath: imagePath ?? this.imagePath,
    type: type ?? this.type,
    readOnly: readOnly ?? this.readOnly,
    removable: removable ?? this.removable,
    enableFua: enableFua ?? this.enableFua,
    desiredEnabled: desiredEnabled ?? this.desiredEnabled,
    managedFile: managedFile ?? this.managedFile,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    documentUri: documentUri ?? this.documentUri,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'imagePath': imagePath,
    'type': type.name,
    'readOnly': readOnly,
    'removable': removable,
    'enableFua': enableFua,
    'desiredEnabled': desiredEnabled,
    'managedFile': managedFile,
    'sizeBytes': sizeBytes,
    'documentUri': documentUri,
  };
  factory VirtualDisk.fromJson(Map<String, dynamic> json) => VirtualDisk(
    id: json['id'] as String,
    name: json['name'] as String,
    imagePath: json['imagePath'] as String,
    type: json['type'] == 'cdrom'
        ? VirtualDiskType.cdrom
        : VirtualDiskType.disk,
    readOnly: json['readOnly'] == true,
    removable: json['removable'] != false,
    enableFua: json['enableFua'] == true,
    desiredEnabled: json['desiredEnabled'] == true,
    managedFile: json['managedFile'] == true,
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    documentUri: json['documentUri'] as String?,
  );
}
