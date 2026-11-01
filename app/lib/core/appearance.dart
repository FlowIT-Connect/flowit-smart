import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Thème visuel Solea. `solea` = thème d'origine (clair / sombre / système).
const appThemes = ['solea', 'dark_glass', 'light_glass', 'orange_glass', 'blue_glass', 'green_glass', 'premium_black', 'custom'];

/// Couleurs proposées pour le thème personnalisé.
const customAccents = <Color>[
  Color(0xFFFF9F2E), Color(0xFFFF6B6B), Color(0xFFF472B6), Color(0xFFA78BFA), Color(0xFF60A5FA),
  Color(0xFF22C5DA), Color(0xFF34D399), Color(0xFFA3E635), Color(0xFFFACC15), Color(0xFFD4A64A),
];

/// Catégorie de la bibliothèque des arrière-plans.
class BackgroundCategory {
  final String key;
  final IconData icon;
  final List<Color> colors;

  const BackgroundCategory(this.key, this.icon, this.colors);

  String get labelKey => 'bgLib.$key';
}

/// Bibliothèque des arrière-plans : `assets/backgrounds/<catégorie>_<n>.jpg`,
/// avec un dégradé de secours tant qu'une photo manque.
class BackgroundLibrary {
  static const imagesPerCategory = 3;

  static const categories = <BackgroundCategory>[
    BackgroundCategory('nature', Icons.forest_rounded, [Color(0xFF1F3B2C), Color(0xFF3F6B45), Color(0xFF0E1A12)]),
    BackgroundCategory('paysage', Icons.landscape_rounded, [Color(0xFF2B3A5C), Color(0xFFB0684A), Color(0xFF1A1424)]),
    BackgroundCategory('architecture_moderne', Icons.apartment_rounded, [Color(0xFF3A3F47), Color(0xFF8C939C), Color(0xFF15181C)]),
    BackgroundCategory('maison_contemporaine', Icons.house_rounded, [Color(0xFF4A3A2C), Color(0xFFC7A27A), Color(0xFF1B1510)]),
    BackgroundCategory('interieur_luxe', Icons.chair_rounded, [Color(0xFF3B2A1A), Color(0xFFB8893F), Color(0xFF120C07)]),
    BackgroundCategory('abstrait_couleurs', Icons.blur_on_rounded, [Color(0xFF6D28D9), Color(0xFFDB2777), Color(0xFF0F172A)]),
    BackgroundCategory('technologie', Icons.memory_rounded, [Color(0xFF0B3B5C), Color(0xFF0EA5B7), Color(0xFF050B14)]),
    BackgroundCategory('minimaliste', Icons.crop_square_rounded, [Color(0xFF52525B), Color(0xFFA1A1AA), Color(0xFF18181B)]),
  ];

  static List<String> imagesOf(BackgroundCategory c) => [for (var i = 1; i <= imagesPerCategory; i++) '${c.key}_$i'];

  static BackgroundCategory? categoryOfImage(String key) {
    final i = key.lastIndexOf('_');
    if (i <= 0) return null;
    final cat = key.substring(0, i);
    for (final c in categories) {
      if (c.key == cat) return c;
    }
    return null;
  }

  static int variantOf(String key) => int.tryParse(key.substring(key.lastIndexOf('_') + 1)) ?? 1;

  static Map<String, String> _assets = const {};

  static Future<void> load([AssetBundle? bundle]) async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(bundle ?? rootBundle);
      final found = <String, String>{};
      for (final path in manifest.listAssets()) {
        final m = RegExp(r'^assets/backgrounds/([a-z_]+_[0-9]+)\.(jpg|jpeg|png|webp)$').firstMatch(path);
        if (m != null) found[m.group(1)!] = path;
      }
      _assets = found;
    } catch (_) {
      _assets = const {};
    }
  }

  static void debugSet(Map<String, String> assets) => _assets = assets;

  static String? assetFor(String key) => _assets[key];
}

/// Préférences d'apparence de l'utilisateur (enregistrées dans son profil et
/// gardées sur l'appareil pour un démarrage immédiat).
@immutable
class Appearance {
  final String theme;

  /// Couleur d'accent du thème personnalisé.
  final Color accent;

  /// Arrière-plan : null = lumières d'origine ; `lib:<clé>` = bibliothèque ;
  /// `photo:<chemin>` = photo importée (bucket backgrounds).
  final String? background;

  /// Flou de l'arrière-plan (0 à 40).
  final double blur;

  /// Luminosité de l'arrière-plan (-0,6 = assombri, 0,3 = éclairci).
  final double brightness;

  /// Opacité du verre des cartes (0,4 = très transparent, 1,8 = plus couvrant).
  final double glassOpacity;

  const Appearance({
    this.theme = 'solea',
    this.accent = const Color(0xFFFF9F2E),
    this.background,
    this.blur = 14,
    this.brightness = -.25,
    this.glassOpacity = 1,
  });

  static const defaults = Appearance();

  bool get isDefault => this == defaults;

  String? get photoPath => background != null && background!.startsWith('photo:') ? background!.substring(6) : null;
  String? get libraryKey => background != null && background!.startsWith('lib:') ? background!.substring(4) : null;

  factory Appearance.fromJson(Object? j) {
    if (j is! Map) return defaults;
    double n(Object? v, double min, double max, double def) => v is num ? v.toDouble().clamp(min, max) : def;
    final theme = j['theme'];
    final bg = j['background'];
    final accent = j['accent'];
    return Appearance(
      theme: theme is String && appThemes.contains(theme) ? theme : 'solea',
      accent: accent is int ? Color(accent | 0xFF000000) : defaults.accent,
      background: bg is String && (bg.startsWith('lib:') || bg.startsWith('photo:')) && bg.length <= 220 ? bg : null,
      blur: n(j['blur'], 0, 40, defaults.blur),
      brightness: n(j['brightness'], -.6, .3, defaults.brightness),
      glassOpacity: n(j['glass_opacity'], .4, 1.8, defaults.glassOpacity),
    );
  }

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'accent': accent.toARGB32() & 0xFFFFFF,
        'background': background,
        'blur': double.parse(blur.toStringAsFixed(1)),
        'brightness': double.parse(brightness.toStringAsFixed(2)),
        'glass_opacity': double.parse(glassOpacity.toStringAsFixed(2)),
      };

  Appearance copyWith({String? theme, Color? accent, String? background, bool clearBackground = false, double? blur, double? brightness, double? glassOpacity}) =>
      Appearance(
        theme: theme ?? this.theme,
        accent: accent ?? this.accent,
        background: clearBackground ? null : (background ?? this.background),
        blur: blur ?? this.blur,
        brightness: brightness ?? this.brightness,
        glassOpacity: glassOpacity ?? this.glassOpacity,
      );

  /// Mode clair / sombre imposé par le thème (null : réglage clair / sombre / système).
  ThemeMode? get forcedMode => switch (theme) {
        'solea' => null,
        'light_glass' => ThemeMode.light,
        _ => ThemeMode.dark,
      };

  /// Couleurs du thème, dérivées des couleurs Solea d'origine.
  FlowColors colors(Brightness b) {
    final base = b == Brightness.light ? FlowColors.light : FlowColors.dark;
    final themed = switch (theme) {
      'orange_glass' => FlowColors.dark.variant(
          backdrop: const Color(0xFF241307),
          blobs: const [Color(0xFFE0701A), Color(0xFF8A3B12), Color(0xFFF59E0B), Color(0xFF7C2D12), Color(0xFFC2410C)],
        ),
      'blue_glass' => FlowColors.dark.variant(
          accent: const Color(0xFF60A5FA),
          backdrop: const Color(0xFF0B1424),
          blobs: const [Color(0xFF1D4ED8), Color(0xFF0E7490), Color(0xFF3B82F6), Color(0xFF312E81), Color(0xFF155E75)],
        ),
      'green_glass' => FlowColors.dark.variant(
          accent: const Color(0xFF34D399),
          backdrop: const Color(0xFF0B1A12),
          blobs: const [Color(0xFF15803D), Color(0xFF3F6212), Color(0xFF059669), Color(0xFF14532D), Color(0xFF4D7C0F)],
        ),
      'premium_black' => FlowColors.dark.variant(
          accent: const Color(0xFFD4A64A),
          backdrop: const Color(0xFF050505),
          blobs: const [Color(0xFF262626), Color(0xFF3F3A2E), Color(0xFF171717), Color(0xFF4A3F26), Color(0xFF1F1F1F)],
          glass: const Color(0x14FFFFFF),
          glassStrong: const Color(0x24FFFFFF),
        ),
      'custom' => FlowColors.dark.variant(
          accent: accent,
          backdrop: Color.lerp(const Color(0xFF0E0E10), accent, .12),
          blobs: [
            Color.lerp(accent, Colors.black, .35)!,
            Color.lerp(accent, const Color(0xFF1E1B4B), .55)!,
            accent,
            Color.lerp(accent, Colors.black, .6)!,
            Color.lerp(accent, const Color(0xFF7C2D12), .5)!,
          ],
        ),
      _ => base, // solea, dark_glass, light_glass
    };
    return themed.withGlassOpacity(glassOpacity);
  }

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.theme == theme &&
      other.accent.toARGB32() == accent.toARGB32() &&
      other.background == background &&
      other.blur == blur &&
      other.brightness == brightness &&
      other.glassOpacity == glassOpacity;

  @override
  int get hashCode => Object.hash(theme, accent.toARGB32(), background, blur, brightness, glassOpacity);
}

/// Apparence en cours ; enregistrée sur l'appareil à chaque changement.
class AppearanceController extends ValueNotifier<Appearance> {
  AppearanceController([super.value = Appearance.defaults]);

  static final instance = AppearanceController();

  /// Photo d'arrière-plan importée, gardée en mémoire (et sur l'appareil).
  Uint8List? photoBytes;

  static const _key = 'appearance';
  static const _photoKey = 'appearance.photo';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) value = Appearance.fromJson(jsonDecode(raw));
      final photo = prefs.getString(_photoKey);
      if (photo != null && value.photoPath != null) photoBytes = base64Decode(photo);
    } catch (_) {}
  }

  Future<void> set(Appearance a, {Uint8List? photo}) async {
    if (photo != null) photoBytes = photo;
    if (a.photoPath == null) photoBytes = null;
    value = a;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(a.toJson()));
      if (photoBytes != null) {
        await prefs.setString(_photoKey, base64Encode(photoBytes!));
      } else {
        await prefs.remove(_photoKey);
      }
    } catch (_) {}
  }
}
