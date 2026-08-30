import 'dart:convert';

enum ModelType { general, anime, face }

ModelType _typeFromString(String s) {
  switch (s) {
    case 'general':
      return ModelType.general;
    case 'anime':
      return ModelType.anime;
    case 'face':
      return ModelType.face;
    default:
      throw ArgumentError('Unknown ModelType: $s');
  }
}

String _typeToString(ModelType t) => t.name;

/// Immutable CatalogEntry describing a downloadable Model.
/// Mirrors ADRs 0002 & 0004 and CONTEXT.md CatalogEntry term.
class CatalogEntry {
  final String id;
  final String name;
  final int scale; // e.g., 4
  final ModelType type;
  final int inputSize; // e.g., 128
  final int fileSize;
  final String sha256;
  final String url;
  final String license;
  final String version;
  final bool bundled;

  const CatalogEntry({
    required this.id,
    required this.name,
    required this.scale,
    required this.type,
    required this.inputSize,
    required this.fileSize,
    required this.sha256,
    required this.url,
    required this.license,
    required this.version,
    this.bundled = false,
  });

  factory CatalogEntry.fromJson(Map<String, dynamic> json) {
    return CatalogEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      scale: json['scale'] as int,
      type: _typeFromString(json['type'] as String),
      inputSize: json['inputSize'] as int,
      fileSize: json['fileSize'] as int,
      sha256: json['sha256'] as String,
      url: json['url'] as String,
      license: json['license'] as String,
      version: json['version'] as String,
      bundled: json['bundled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'scale': scale,
        'type': _typeToString(type),
        'inputSize': inputSize,
        'fileSize': fileSize,
        'sha256': sha256,
        'url': url,
        'license': license,
        'version': version,
        'bundled': bundled,
      };

  static List<CatalogEntry> listFromJson(String jsonStr) {
    final List<dynamic> decoded = json.decode(jsonStr) as List<dynamic>;
    return decoded
        .map((e) => CatalogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
