import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Catégorie de la bibliothèque d'images des pièces.
class RoomImageCategory {
  final String key;
  final IconData icon;

  /// Teintes de l'illustration affichée tant qu'aucune photo n'est livrée.
  final List<Color> colors;

  const RoomImageCategory(this.key, this.icon, this.colors);

  /// Clé de traduction du nom de la catégorie.
  String get labelKey => 'roomLib.$key';
}

/// Bibliothèque Solea : 10 catégories, plusieurs images chacune.
///
/// Une image de la bibliothèque est désignée par `<catégorie>_<n>` (colonne
/// rooms.image_key). Les photos sont livrées dans `assets/rooms/<catégorie>_<n>.jpg`
/// (ou .webp/.png) : il suffit de déposer un fichier pour qu'il remplace
/// l'illustration de secours, sans toucher au code.
class RoomLibrary {
  static const imagesPerCategory = 3;

  static const categories = <RoomImageCategory>[
    RoomImageCategory('salon_moderne', Icons.weekend_rounded, [Color(0xFFE0A46B), Color(0xFF7C5236), Color(0xFF2E2420)]),
    RoomImageCategory('salon_classique', Icons.chair_rounded, [Color(0xFFD9B98C), Color(0xFF8A5A3B), Color(0xFF3A2619)]),
    RoomImageCategory('chambre_parentale', Icons.bed_rounded, [Color(0xFFC9A6D8), Color(0xFF6B4E7E), Color(0xFF261D33)]),
    RoomImageCategory('chambre_enfant', Icons.child_care_rounded, [Color(0xFFF6B6C8), Color(0xFF9A6FB0), Color(0xFF3B2A4A)]),
    RoomImageCategory('cuisine_moderne', Icons.kitchen_rounded, [Color(0xFFE8D6B8), Color(0xFF8C7A63), Color(0xFF2F2A25)]),
    RoomImageCategory('salle_de_bain', Icons.bathtub_rounded, [Color(0xFFA8DCE6), Color(0xFF4F8C9E), Color(0xFF1B3038)]),
    RoomImageCategory('bureau', Icons.desk_rounded, [Color(0xFFB8C8A0), Color(0xFF5E7351), Color(0xFF22291D)]),
    RoomImageCategory('jardin_terrasse', Icons.yard_rounded, [Color(0xFFB5E08C), Color(0xFF4F8A3C), Color(0xFF1C3018)]),
    RoomImageCategory('garage', Icons.garage_rounded, [Color(0xFFB7BEC7), Color(0xFF5B6470), Color(0xFF1F2328)]),
    RoomImageCategory('entree_couloir', Icons.door_front_door_rounded, [Color(0xFFE6C79A), Color(0xFF8E6C47), Color(0xFF2D2219)]),
  ];

  static RoomImageCategory? category(String key) {
    for (final c in categories) {
      if (c.key == key) return c;
    }
    return null;
  }

  /// Toutes les images d'une catégorie (`salon_moderne_1`, …).
  static List<String> imagesOf(RoomImageCategory c) => [for (var i = 1; i <= imagesPerCategory; i++) '${c.key}_$i'];

  /// Catégorie d'une image de la bibliothèque (`salon_moderne_2` → salon_moderne).
  static RoomImageCategory? categoryOfImage(String imageKey) {
    final i = imageKey.lastIndexOf('_');
    return i <= 0 ? null : category(imageKey.substring(0, i));
  }

  /// Variante (1, 2, 3…) d'une image, pour varier les illustrations de secours.
  static int variantOf(String imageKey) => int.tryParse(imageKey.substring(imageKey.lastIndexOf('_') + 1)) ?? 1;

  static bool isValidKey(String? key) => key != null && categoryOfImage(key) != null && RegExp(r'^[a-z_]+_[0-9]+$').hasMatch(key);

  /// Image par défaut d'une pièce selon son icône.
  static String defaultImageFor(String? roomIcon) => switch (roomIcon) {
        'sofa' => 'salon_moderne_1',
        'dining' => 'salon_classique_1',
        'bed' => 'chambre_parentale_1',
        'child' => 'chambre_enfant_1',
        'kitchen' => 'cuisine_moderne_1',
        'bath' => 'salle_de_bain_1',
        'office' => 'bureau_1',
        'garden' => 'jardin_terrasse_1',
        'garage' => 'garage_1',
        'door' || 'stairs' => 'entree_couloir_1',
        _ => 'salon_moderne_1',
      };

  // --------------------------------------------------------- Photos livrées
  static Map<String, String> _assets = const {};

  static Future<void> load([AssetBundle? bundle]) async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(bundle ?? rootBundle);
      final found = <String, String>{};
      for (final path in manifest.listAssets()) {
        final m = RegExp(r'^assets/rooms/([a-z_]+_[0-9]+)\.(jpg|jpeg|png|webp)$').firstMatch(path);
        if (m != null) found[m.group(1)!] = path;
      }
      _assets = found;
    } catch (_) {
      _assets = const {};
    }
  }

  /// Utilisé par les tests pour simuler des photos livrées.
  static void debugSet(Map<String, String> assets) => _assets = assets;

  /// Photo livrée pour cette image, ou null (illustration de secours).
  static String? assetFor(String imageKey) => _assets[imageKey];
}

/// Cadrage d'une image de pièce : point visé (-1 à 1) et zoom (1 à 3).
@immutable
class RoomImageFit {
  final double x;
  final double y;
  final double zoom;

  const RoomImageFit({this.x = 0, this.y = 0, this.zoom = 1});

  static const centered = RoomImageFit();

  factory RoomImageFit.fromJson(Object? j) {
    if (j is! Map) return centered;
    double v(Object? n, double min, double max, double def) => n is num ? n.toDouble().clamp(min, max) : def;
    return RoomImageFit(x: v(j['x'], -1, 1, 0), y: v(j['y'], -1, 1, 0), zoom: v(j['zoom'], 1, 3, 1));
  }

  Map<String, dynamic> toJson() => {
        'x': double.parse(x.toStringAsFixed(3)),
        'y': double.parse(y.toStringAsFixed(3)),
        'zoom': double.parse(zoom.toStringAsFixed(3)),
      };

  RoomImageFit copyWith({double? x, double? y, double? zoom}) => RoomImageFit(
        x: (x ?? this.x).clamp(-1.0, 1.0),
        y: (y ?? this.y).clamp(-1.0, 1.0),
        zoom: (zoom ?? this.zoom).clamp(1.0, 3.0),
      );

  Alignment get alignment => Alignment(x, y);

  @override
  bool operator ==(Object other) => other is RoomImageFit && other.x == x && other.y == y && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(x, y, zoom);
}
