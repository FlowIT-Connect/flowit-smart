import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'glass.dart';

/// Identité visuelle Solea (aucune ressource Smart Life, §5.11).
///
/// Direction : « lumière du soleil » en verre dépoli (glassmorphism). Un fond
/// de lumières chaudes floutées, des cartes translucides bordées d'un filet
/// clair, un orange soleil comme unique accent et de grands chiffres fins.
/// Les appareils allumés prennent une teinte de verre ambré, les appareils
/// éteints restent en verre neutre.
class AppTheme {
  static const seed = Color(0xFFF28C1B);
  static const fontFamily = 'Manrope';
  static const fontFallback = ['IBMPlexSansArabic'];

  static ThemeData light() => _build(FlowColors.light, Brightness.light);

  static ThemeData dark() => _build(FlowColors.dark, Brightness.dark);

  static ThemeData _build(FlowColors c, Brightness brightness) {
    final base = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final scheme = base.copyWith(
      primary: c.brand,
      onPrimary: c.onBrand,
      primaryContainer: c.brandSoft,
      onPrimaryContainer: c.brandInk,
      secondary: c.brandDeep,
      secondaryContainer: c.chip,
      onSecondaryContainer: c.ink,
      tertiary: c.violet,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.inkSoft,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surfaceAlt,
      surfaceContainerHigh: c.surfaceAlt,
      surfaceContainerHighest: c.chip,
      outline: c.inkFaint,
      outlineVariant: c.line,
      error: c.danger,
      errorContainer: c.dangerSoft,
      onErrorContainer: c.dangerInk,
    );
    final text = _text(scheme);
    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));
    const buttonPadding = EdgeInsets.symmetric(horizontal: 22, vertical: 14);
    final buttonText = text.labelLarge?.copyWith(fontWeight: FontWeight.w700);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      textTheme: text,
      // Transparent : chaque page est posée sur le fond de verre (GlassPageTransitions).
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: c.background,
      extensions: [c],
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const GlassPageTransitions(),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        foregroundColor: c.ink,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: c.ink),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: c.glass,
        surfaceTintColor: Colors.transparent,
        shadowColor: c.shadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: c.glassBorder)),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.inkSoft, size: 22),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsetsDirectional.only(start: 18, end: 14),
        iconColor: c.inkSoft,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: c.ink),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: c.inkSoft),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        minVerticalPadding: 12,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.field,
        contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: c.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: c.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: c.brand, width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: c.danger)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: c.danger, width: 1.6)),
        labelStyle: TextStyle(color: c.inkSoft),
        hintStyle: TextStyle(color: c.inkFaint),
        prefixIconColor: c.inkSoft,
        suffixIconColor: c.inkSoft,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: pill,
          padding: buttonPadding,
          textStyle: buttonText,
          minimumSize: const Size(64, 50),
          // Actions principales en noir (blanc en sombre), l'orange reste l'accent.
          backgroundColor: c.ink,
          foregroundColor: c.background,
          disabledBackgroundColor: c.chip,
          disabledForegroundColor: c.inkFaint,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: pill, padding: buttonPadding, textStyle: buttonText, elevation: 0),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: pill, padding: buttonPadding, textStyle: buttonText, foregroundColor: c.ink, side: BorderSide(color: c.line)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: pill, textStyle: buttonText, foregroundColor: c.brandStrong),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: c.inkSoft)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.ink,
        foregroundColor: c.background,
        elevation: 2,
        highlightElevation: 4,
        shape: pill,
        extendedTextStyle: buttonText,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.chip,
        selectedColor: c.brandSoft,
        disabledColor: c.chip.withValues(alpha: .5),
        side: BorderSide.none,
        shape: pill,
        labelStyle: text.labelLarge?.copyWith(color: c.ink, fontWeight: FontWeight.w600),
        secondaryLabelStyle: text.labelLarge?.copyWith(color: c.brandInk, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        iconTheme: IconThemeData(color: c.inkSoft, size: 18),
        checkmarkColor: c.brandInk,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return s.contains(WidgetState.selected) ? c.surface : c.inkFaint.withValues(alpha: .6);
          return s.contains(WidgetState.selected) ? Colors.white : c.inkFaint;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return s.contains(WidgetState.selected) ? c.brand.withValues(alpha: .35) : c.chip.withValues(alpha: .6);
          return s.contains(WidgetState.selected) ? c.brand : c.chip;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.transparent : c.line),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 14,
        activeTrackColor: c.brand,
        inactiveTrackColor: c.chip,
        thumbColor: Colors.white,
        overlayColor: c.brand.withValues(alpha: .12),
        valueIndicatorColor: c.ink,
        valueIndicatorTextStyle: text.labelLarge?.copyWith(color: c.background, fontWeight: FontWeight.w700),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 13, elevation: 3, pressedElevation: 6),
        trackShape: const RoundedRectSliderTrackShape(),
        tickMarkShape: SliderTickMarkShape.noTickMark,
        showValueIndicator: ShowValueIndicator.onDrag,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.brand, linearTrackColor: c.chip),
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.brand,
        indicatorShape: pill,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: s.contains(WidgetState.selected) ? c.ink : c.inkSoft),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? c.onBrand : c.inkSoft),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: c.brand,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        selectedIconTheme: IconThemeData(color: c.onBrand, size: 24),
        unselectedIconTheme: IconThemeData(color: c.inkSoft, size: 24),
        selectedLabelTextStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: c.ink),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: c.inkSoft),
        minWidth: 96,
        groupAlignment: -0.85,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: c.ink),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.sheet,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.sheet,
        dragHandleColor: c.inkFaint,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: c.shadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: c.cardBorder)),
        textStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: c.ink),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: c.chip,
          selectedBackgroundColor: c.surface,
          selectedForegroundColor: c.ink,
          foregroundColor: c.inkSoft,
          side: BorderSide(color: c.chip, width: 3),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.background, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(10)),
        textStyle: text.labelMedium?.copyWith(color: c.background, fontWeight: FontWeight.w600),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        iconColor: c.inkSoft,
        collapsedIconColor: c.inkSoft,
      ),
      badgeTheme: BadgeThemeData(backgroundColor: c.brand, textColor: c.onBrand),
    );
  }

  static TextTheme _text(ColorScheme scheme) {
    final t = Typography.material2021(platform: TargetPlatform.android).englishLike.apply(
          fontFamily: fontFamily,
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        );
    TextStyle? w(TextStyle? s, FontWeight weight, [double? spacing]) =>
        s?.copyWith(fontWeight: weight, letterSpacing: spacing, fontFamilyFallback: fontFallback);
    return t.copyWith(
      displayLarge: w(t.displayLarge, FontWeight.w300, -2),
      displayMedium: w(t.displayMedium, FontWeight.w300, -1.5),
      displaySmall: w(t.displaySmall, FontWeight.w800, -1),
      headlineLarge: w(t.headlineLarge, FontWeight.w700, -.8),
      headlineMedium: w(t.headlineMedium, FontWeight.w700, -.6),
      headlineSmall: w(t.headlineSmall, FontWeight.w700, -.4),
      titleLarge: w(t.titleLarge, FontWeight.w700, -.2),
      titleMedium: w(t.titleMedium, FontWeight.w700, -.1),
      titleSmall: w(t.titleSmall, FontWeight.w700, 0),
      bodyLarge: w(t.bodyLarge, FontWeight.w500, 0),
      bodyMedium: w(t.bodyMedium, FontWeight.w500, 0),
      bodySmall: w(t.bodySmall, FontWeight.w500, .1),
      labelLarge: w(t.labelLarge, FontWeight.w600, .1),
      labelMedium: w(t.labelMedium, FontWeight.w600, .2),
      labelSmall: w(t.labelSmall, FontWeight.w600, .3),
    );
  }
}

/// Jetons de couleur Solea, disponibles via `context.flow`.
@immutable
class FlowColors extends ThemeExtension<FlowColors> {
  const FlowColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.sheet,
    required this.field,
    required this.chip,
    required this.line,
    required this.cardBorder,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.brand,
    required this.brandStrong,
    required this.brandDeep,
    required this.brandSoft,
    required this.brandInk,
    required this.onBrand,
    required this.tileOff,
    required this.tileOn,
    required this.tileOnInk,
    required this.tileOnInkSoft,
    required this.navBar,
    required this.glowA,
    required this.glowB,
    required this.amber,
    required this.orange,
    required this.blue,
    required this.violet,
    required this.cyan,
    required this.pink,
    required this.success,
    required this.warning,
    required this.danger,
    required this.dangerSoft,
    required this.dangerInk,
    required this.shadow,
    required this.glass,
    required this.glassStrong,
    required this.glassBorder,
    required this.backdrop,
    required this.blobs,
  });

  final Color background, surface, surfaceAlt, sheet, field, chip, line, cardBorder;
  final Color ink, inkSoft, inkFaint;
  final Color brand, brandStrong, brandDeep, brandSoft, brandInk, onBrand;
  final Color tileOff, tileOn, tileOnInk, tileOnInkSoft, navBar;
  final Color glowA, glowB;
  final Color amber, orange, blue, violet, cyan, pink;
  final Color success, warning, danger, dangerSoft, dangerInk, shadow;

  /// Verre dépoli : remplissage des cartes, version plus couvrante (barres,
  /// panneaux) et filet clair qui dessine le bord du verre.
  final Color glass, glassStrong, glassBorder;

  /// Fond de scène et taches de lumière floutées peintes derrière le verre.
  final Color backdrop;
  final List<Color> blobs;

  static const light = FlowColors(
    background: Color(0xFFFBF8F4),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF7F3EE),
    sheet: Color(0xFFFFFBF6),
    field: Color(0xB3FFFFFF),
    chip: Color(0x99F2E8DC),
    line: Color(0xFFE9E2D8),
    cardBorder: Color(0xB3FFFFFF),
    ink: Color(0xFF1F1C19),
    inkSoft: Color(0xFF71695F),
    inkFaint: Color(0xFFA9A094),
    brand: Color(0xFFF28C1B),
    brandStrong: Color(0xFFD9730A),
    brandDeep: Color(0xFFB45A07),
    brandSoft: Color(0xFFFDEBD4),
    brandInk: Color(0xFF8F4706),
    onBrand: Color(0xFFFFFFFF),
    tileOff: Color(0x80FFFFFF),
    tileOn: Color(0xB3FFD7A6),
    tileOnInk: Color(0xFF1F1C19),
    tileOnInkSoft: Color(0xFF7A6248),
    navBar: Color(0x8CFFFFFF),
    glowA: Color(0x26FFC23D),
    glowB: Color(0x14F28C1B),
    amber: Color(0xFFF5A524),
    orange: Color(0xFFEE6A1F),
    blue: Color(0xFF3B82F6),
    violet: Color(0xFF7C5CFF),
    cyan: Color(0xFF0EA5B7),
    pink: Color(0xFFE5487D),
    success: Color(0xFF1F9D63),
    warning: Color(0xFFD9730A),
    danger: Color(0xFFDC3B42),
    dangerSoft: Color(0xFFFDE6E3),
    dangerInk: Color(0xFF8E1C22),
    shadow: Color(0x141F1C19),
    glass: Color(0x80FFFFFF),
    glassStrong: Color(0xA6FFFFFF),
    glassBorder: Color(0xB3FFFFFF),
    backdrop: Color(0xFFF5E6D6),
    blobs: [Color(0xFFFFC163), Color(0xFFB9C99A), Color(0xFFF59A5B), Color(0xFFC9B7E8), Color(0xFFF4B39C)],
  );

  static const dark = FlowColors(
    background: Color(0xFF12100D),
    surface: Color(0xFF1C1915),
    surfaceAlt: Color(0xFF23201B),
    sheet: Color(0xFF1A1713),
    field: Color(0x26FFFFFF),
    chip: Color(0x26FFFFFF),
    line: Color(0xFF353029),
    cardBorder: Color(0x33FFFFFF),
    ink: Color(0xFFF7F2EA),
    inkSoft: Color(0xFFB5AB9E),
    inkFaint: Color(0xFF7B7166),
    brand: Color(0xFFFF9F2E),
    brandStrong: Color(0xFFFFB45C),
    brandDeep: Color(0xFFF28C1B),
    brandSoft: Color(0xFF3B2813),
    brandInk: Color(0xFFFFC98A),
    onBrand: Color(0xFF231200),
    tileOff: Color(0x1FFFFFFF),
    tileOn: Color(0x66E07A22),
    tileOnInk: Color(0xFFFFF5E8),
    tileOnInkSoft: Color(0xFFE2C29C),
    navBar: Color(0x40FFFFFF),
    glowA: Color(0x1FFFB13D),
    glowB: Color(0x14F28C1B),
    amber: Color(0xFFFFB547),
    orange: Color(0xFFFF7A3D),
    blue: Color(0xFF60A5FA),
    violet: Color(0xFF9B87FF),
    cyan: Color(0xFF22C5DA),
    pink: Color(0xFFF472B6),
    success: Color(0xFF34D399),
    warning: Color(0xFFFFB45C),
    danger: Color(0xFFFF6369),
    dangerSoft: Color(0xFF3A1518),
    dangerInk: Color(0xFFFFB4B6),
    shadow: Color(0x66000000),
    glass: Color(0x1FFFFFFF),
    glassStrong: Color(0x33FFFFFF),
    glassBorder: Color(0x33FFFFFF),
    backdrop: Color(0xFF1B140F),
    blobs: [Color(0xFFA9561D), Color(0xFF45522F), Color(0xFFC46A26), Color(0xFF41315C), Color(0xFF7A3B2A)],
  );

  /// Dégradé soleil Solea (logo, écran de connexion), du jaune à l'orange.
  LinearGradient get brandGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFC93C), Color(0xFFF7941D), Color(0xFFEE6A1F)],
        stops: [0, .55, 1],
      );

  /// Carte « résumé » sombre de l'accueil, façon pilule énergie.
  Color get panel => ink == FlowColors.light.ink ? const Color(0xFF1F1C19) : const Color(0xFF26221D);

  /// Dégradé du verre : plus clair en haut à gauche, comme un reflet.
  LinearGradient get glassGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [glassStrong, glass],
      );

  @override
  FlowColors copyWith() => this;

  @override
  FlowColors lerp(ThemeExtension<FlowColors>? other, double t) => t < .5 ? this : (other as FlowColors? ?? this);
}

extension FlowTheme on BuildContext {
  FlowColors get flow => Theme.of(this).extension<FlowColors>() ?? FlowColors.light;
}

/// Préférence d'apparence (système, clair, sombre), mémorisée sur l'appareil.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController([super.value = ThemeMode.system]);

  static final instance = ThemeController();

  Future<void> load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString('theme_mode');
      value = ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => ThemeMode.system);
    } catch (_) {}
  }

  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      await (await SharedPreferences.getInstance()).setString('theme_mode', mode.name);
    } catch (_) {}
  }
}
