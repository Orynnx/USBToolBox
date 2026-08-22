enum VirtualDiskType { disk, cdrom }

enum DiskBackingOwnership { linked, managedCopy, managedNew }

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
    required this.ownership,
    required this.sizeBytes,
    this.sourceUri,
    this.managedDocumentUri,
  });

  final String id, name, imagePath;
  final VirtualDiskType type;
  final bool readOnly, removable, enableFua, desiredEnabled;
  final DiskBackingOwnership ownership;
  final int sizeBytes;

  /// Persisted read grant for a user-owned source. Never delete this URI.
  final String? sourceUri;

  /// URI of a file created by HyperUSB. Only this URI may be deleted.
  final String? managedDocumentUri;

  bool get canDeleteBacking =>
      ownership != DiskBackingOwnership.linked && managedDocumentUri != null;

  VirtualDisk copyWith({
    String? name,
    String? imagePath,
    VirtualDiskType? type,
    bool? readOnly,
    bool? removable,
    bool? enableFua,
    bool? desiredEnabled,
    DiskBackingOwnership? ownership,
    int? sizeBytes,
    String? sourceUri,
    String? managedDocumentUri,
  }) => VirtualDisk(
    id: id,
    name: name ?? this.name,
    imagePath: imagePath ?? this.imagePath,
    type: type ?? this.type,
    readOnly: readOnly ?? this.readOnly,
    removable: removable ?? this.removable,
    enableFua: enableFua ?? this.enableFua,
    desiredEnabled: desiredEnabled ?? this.desiredEnabled,
    ownership: ownership ?? this.ownership,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    sourceUri: sourceUri ?? this.sourceUri,
    managedDocumentUri: managedDocumentUri ?? this.managedDocumentUri,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': 2,
    'id': id,
    'name': name,
    'imagePath': imagePath,
    'type': type.name,
    'readOnly': readOnly,
    'removable': removable,
    'enableFua': enableFua,
    'desiredEnabled': desiredEnabled,
    'ownership': ownership.name,
    'sizeBytes': sizeBytes,
    'sourceUri': sourceUri,
    'managedDocumentUri': managedDocumentUri,
  };

  factory VirtualDisk.fromJson(Map<String, dynamic> json) {
    final legacyManaged = json['managedFile'] == true;
    final ownership = DiskBackingOwnership.values.firstWhere(
      (value) => value.name == json['ownership'],
      orElse: () => legacyManaged
          ? DiskBackingOwnership.managedCopy
          : DiskBackingOwnership.linked,
    );
    final legacyDocumentUri = json['documentUri'] as String?;
    return VirtualDisk(
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
      ownership: ownership,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      sourceUri:
          json['sourceUri'] as String? ??
          (ownership == DiskBackingOwnership.linked ? legacyDocumentUri : null),
      managedDocumentUri:
          json['managedDocumentUri'] as String? ??
          (ownership == DiskBackingOwnership.linked ? null : legacyDocumentUri),
    );
  }
}
