import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../catalog/catalog_entry.dart';

enum PresetContentType {
  photo(
    label: 'Photos',
    icon: LucideIcons.camera,
    activeIcon: LucideIcons.camera,
    description: 'Realistic photos, portraits, and landscapes',
  ),
  anime(
    label: 'Art & Anime',
    icon: LucideIcons.palette,
    activeIcon: LucideIcons.palette,
    description: 'Anime, manga, digital illustrations, and 2D art',
  );

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String description;

  const PresetContentType({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.description,
  });
}

enum PresetQualityTier {
  lightning(
    label: 'Lightning',
    badge: 'Lightning (<1s)',
    icon: LucideIcons.zap,
    description: 'Ultra-fast upscale on mobile GPU/CPU',
    tier: ModelTier.fast,
  ),
  balanced(
    label: 'Balanced',
    badge: 'Balanced',
    icon: LucideIcons.scale,
    description: 'Optimal balance of speed and clarity',
    tier: ModelTier.balanced,
  ),
  ultraQuality(
    label: 'Ultra Quality',
    badge: 'Ultra Quality',
    icon: LucideIcons.sparkles,
    description: 'Maximum textures and fine details',
    tier: ModelTier.quality,
  );

  final String label;
  final String badge;
  final IconData icon;
  final String description;
  final ModelTier tier;

  const PresetQualityTier({
    required this.label,
    required this.badge,
    required this.icon,
    required this.description,
    required this.tier,
  });
}

class PresetResolver {
  static CatalogEntry resolveBestModel({
    required List<CatalogEntry> catalog,
    required PresetContentType contentType,
    required PresetQualityTier qualityTier,
    required bool useGpu,
  }) {
    if (catalog.isEmpty) {
      throw StateError('Catalog cannot be empty');
    }

    // 1. Filter by content type match
    final typeMatches = catalog.where((e) {
      if (contentType == PresetContentType.anime) {
        return e.type == ModelType.anime;
      } else {
        return e.type == ModelType.general;
      }
    }).toList();

    final candidates = typeMatches.isNotEmpty ? typeMatches : catalog;

    // 2. Filter by tier match
    final tierMatches = candidates.where((e) => e.tier == qualityTier.tier).toList();

    if (tierMatches.isNotEmpty) {
      // If GPU enabled, prefer MNN backend
      if (useGpu) {
        final mnnMatch = tierMatches.firstWhere(
          (e) => e.backend == EngineBackend.mnn,
          orElse: () => tierMatches.first,
        );
        return mnnMatch;
      }
      return tierMatches.first;
    }

    // 3. Fallback: bundled model in candidate type or first candidate
    return candidates.firstWhere(
      (e) => e.bundled,
      orElse: () => candidates.first,
    );
  }
}
