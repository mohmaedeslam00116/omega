import 'dart:convert';

enum ModelType { general, anime, face }

enum ModelRole { denoise, upscale, faceRefine, lineRefine }

enum EngineBackend { tflite, mnn, onnx }

enum ModelTier { fast, balanced, quality }

enum TaskType { anime, photo, general }

TaskType _taskTypeFromString(String? s) {
  if (s != null) {
    switch (s.toLowerCase()) {
      case 'anime':
        return TaskType.anime;
      case 'photo':
        return TaskType.photo;
      case 'general':
      default:
        return TaskType.general;
    }
  }
  return TaskType.general;
}

ModelRole _roleFromString(String? s) {
  if (s != null) {
    switch (s.toLowerCase()) {
      case 'denoise':
        return ModelRole.denoise;
      case 'face_refine':
      case 'facerefine':
        return ModelRole.faceRefine;
      case 'line_refine':
      case 'linerefine':
        return ModelRole.lineRefine;
      case 'upscale':
      default:
        return ModelRole.upscale;
    }
  }
  return ModelRole.upscale;
}

extension ModelTierPresentation on ModelTier {
  String get label {
    switch (this) {
      case ModelTier.fast:
        return 'Ultra Fast';
      case ModelTier.balanced:
        return 'Balanced';
      case ModelTier.quality:
        return 'Ultra Quality';
    }
  }

  String get displayName => label;

  int get bgColorValue {
    switch (this) {
      case ModelTier.fast:
        return 0xFFFEF3C7;
      case ModelTier.balanced:
        return 0xFFE0E7FF;
      case ModelTier.quality:
        return 0xFFF3E8FF;
    }
  }

  int get fgColorValue {
    switch (this) {
      case ModelTier.fast:
        return 0xFF92400E;
      case ModelTier.balanced:
        return 0xFF3730A3;
      case ModelTier.quality:
        return 0xFF6B21A8;
    }
  }
}

EngineBackend _backendFromString(String? s, String url) {
  if (s != null) {
    switch (s.toLowerCase()) {
      case 'mnn':
        return EngineBackend.mnn;
      case 'onnx':
        return EngineBackend.onnx;
      case 'tflite':
        return EngineBackend.tflite;
    }
  }
  if (url.endsWith('.mnn')) return EngineBackend.mnn;
  if (url.endsWith('.onnx')) return EngineBackend.onnx;
  return EngineBackend.tflite;
}

ModelTier _tierFromString(String? s, int fileSize) {
  if (s != null) {
    switch (s.toLowerCase()) {
      case 'fast':
        return ModelTier.fast;
      case 'balanced':
        return ModelTier.balanced;
      case 'quality':
      case 'ultra_quality':
        return ModelTier.quality;
    }
  }
  if (fileSize < 4 * 1024 * 1024) return ModelTier.fast;
  if (fileSize < 12 * 1024 * 1024) return ModelTier.balanced;
  return ModelTier.quality;
}

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
/// Mirrors ADRs 0002 & 0004 & 0010 & 0014 and CONTEXT.md CatalogEntry term.
class CatalogEntry {
  final String id;
  final String name;
  final int scale; // e.g., 4 (or 1 for denoise/refinement)
  final ModelType type;
  final ModelRole role;
  final EngineBackend backend;
  final ModelTier tier;
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
    this.role = ModelRole.upscale,
    this.backend = EngineBackend.tflite,
    this.tier = ModelTier.balanced,
    required this.inputSize,
    required this.fileSize,
    required this.sha256,
    required this.url,
    required this.license,
    required this.version,
    this.bundled = false,
  });

  factory CatalogEntry.fromJson(Map<String, dynamic> json) {
    // Validate required fields
    for (final k in [
      'id',
      'name',
      'scale',
      'type',
      'inputSize',
      'fileSize',
      'sha256',
      'url',
      'license',
      'version'
    ]) {
      if (!json.containsKey(k) || json[k] == null) {
        throw FormatException('Missing required field: $k in $json');
      }
    }
    final scale = json['scale'] as int;
    final inputSize = json['inputSize'] as int;
    final license = json['license'] as String;
    final url = json['url'] as String;
    if (scale != 4 && scale != 1) {
      throw FormatException('Invalid scale $scale for $json');
    }
    if (inputSize != 128) {
      throw FormatException(
          'Invalid inputSize $inputSize, expected 128 for $json');
    }
    if (license.isEmpty) {
      throw FormatException('License must not be empty for $json');
    }
    final fileSize = json['fileSize'] as int;
    return CatalogEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      scale: scale,
      type: _typeFromString(json['type'] as String),
      role: _roleFromString(json['role'] as String?),
      backend: _backendFromString(json['backend'] as String?, url),
      tier: _tierFromString(json['tier'] as String?, fileSize),
      inputSize: inputSize,
      fileSize: fileSize,
      sha256: json['sha256'] as String,
      url: url,
      license: license,
      version: json['version'] as String,
      bundled: json['bundled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'scale': scale,
        'type': _typeToString(type),
        'role': role.name,
        'backend': backend.name,
        'tier': tier.name,
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

/// Immutable ModelBundle entity declaring an end-to-end task pipeline.
class ModelBundle {
  final String id;
  final String name;
  final TaskType taskType;
  final List<String> modelIds;
  final String description;

  const ModelBundle({
    required this.id,
    required this.name,
    required this.taskType,
    required this.modelIds,
    this.description = '',
  });

  factory ModelBundle.fromJson(Map<String, dynamic> json) {
    return ModelBundle(
      id: json['id'] as String,
      name: json['name'] as String,
      taskType: _taskTypeFromString(json['taskType'] as String?),
      modelIds:
          (json['modelIds'] as List<dynamic>).map((e) => e as String).toList(),
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'taskType': taskType.name,
        'modelIds': modelIds,
        'description': description,
      };

  static List<ModelBundle> listFromJson(String jsonStr) {
    final List<dynamic> decoded = json.decode(jsonStr) as List<dynamic>;
    return decoded
        .map((e) => ModelBundle.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
