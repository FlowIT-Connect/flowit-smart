import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Identité visuelle propre à FlowIT (aucune ressource Smart Life, §5.11).
///
/// Direction : « flux de lumière ». Fonds calmes, cartes douces très arrondies,
/// un turquoise FlowIT comme fil conducteur et une couleur d'accent par famille
/// d'appareil (lumière ambrée, climat orangé, volets bleus…). Les appareils
/// allumés s'illuminent, les appareils éteints restent en retrait.
class AppTheme {
  static const seed = Color(0xFF0E9E9A);
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
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      extensions: [c],
      visualDensity: VisualDensity.standard,
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
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: c.shadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: c.cardBorder)),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.brand, width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.danger)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.danger, width: 1.6)),
        labelStyle: TextStyle(color: c.inkSoft),
        hintStyle: TextStyle(color: c.inkFaint),
        prefixIconColor: c.inkSoft,
        suffixIconColor: c.inkSoft,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: pill, padding: buttonPadding, textStyle: buttonText, minimumSize: const Size(64, 50)),
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
        backgroundColor: c.navBar,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.brandSoft,
        indicatorShape: pill,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: s.contains(WidgetState.selected) ? c.ink : c.inkSoft),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? c.brandInk : c.inkSoft),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: c.brandSoft,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        selectedIconTheme: IconThemeData(color: c.brandInk, size: 24),
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
      displayLarge: w(t.displayLarge, FontWeight.w800, -1.5),
      displayMedium: w(t.displayMedium, FontWeight.w800, -1.2),
      displaySmall: w(t.displaySmall, FontWeight.w800, -1),
      headlineLarge: w(t.headlineLarge, FontWeight.w800, -.8),
      headlineMedium: w(t.headlineMedium, FontWeight.w800, -.6),
      headlineSmall: w(t.headlineSmall, FontWeight.w800, -.4),
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

/// Jetons de couleur FlowIT, disponibles via `context.flow`.
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
  });

  final Color background, surface, surfaceAlt, sheet, field, chip, line, cardBorder;
  final Color ink, inkSoft, inkFaint;
  final Color brand, brandStrong, brandDeep, brandSoft, brandInk, onBrand;
  final Color tileOff, tileOn, tileOnInk, tileOnInkSoft, navBar;
  final Color glowA, glowB;
  final Color amber, orange, blue, violet, cyan, pink;
  final Color success, warning, danger, dangerSoft, dangerInk, shadow;

  static const light = FlowColors(
    background: Color(0xFFF2F4F7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF7F8FA),
    sheet: Color(0xFFF7F8FA),
    field: Color(0xFFF1F3F6),
    chip: Color(0xFFE8ECF1),
    line: Color(0xFFDDE3EA),
    cardBorder: Color(0x0F0E1726),
    ink: Color(0xFF0E1726),
    inkSoft: Color(0xFF5A6677),
    inkFaint: Color(0xFF98A2B3),
    brand: Color(0xFF0E9E9A),
    brandStrong: Color(0xFF0A7F7C),
    brandDeep: Color(0xFF0B5563),
    brandSoft: Color(0xFFD5F3F0),
    brandInk: Color(0xFF075E5B),
    onBrand: Color(0xFFFFFFFF),
    tileOff: Color(0xFFE6EAF0),
    tileOn: Color(0xFFFFFFFF),
    tileOnInk: Color(0xFF0E1726),
    tileOnInkSoft: Color(0xFF5A6677),
    navBar: Color(0xF2FFFFFF),
    glowA: Color(0x3314B8A6),
    glowB: Color(0x228B7CFF),
    amber: Color(0xFFF5A524),
    orange: Color(0xFFF26B3A),
    blue: Color(0xFF3B82F6),
    violet: Color(0xFF7C5CFF),
    cyan: Color(0xFF06B6D4),
    pink: Color(0xFFEC4899),
    success: Color(0xFF16A36F),
    warning: Color(0xFFE08A00),
    danger: Color(0xFFDC3B42),
    dangerSoft: Color(0xFFFDE4E4),
    dangerInk: Color(0xFF8E1C22),
    shadow: Color(0x1A0E1726),
  );

  static const dark = FlowColors(
    background: Color(0xFF080C11),
    surface: Color(0xFF121820),
    surfaceAlt: Color(0xFF171E28),
    sheet: Color(0xFF10161E),
    field: Color(0xFF19212C),
    chip: Color(0xFF222B37),
    line: Color(0xFF263040),
    cardBorder: Color(0x14FFFFFF),
    ink: Color(0xFFEEF2F7),
    inkSoft: Color(0xFF97A3B4),
    inkFaint: Color(0xFF5F6B7C),
    brand: Color(0xFF2DD4C4),
    brandStrong: Color(0xFF5EE3D6),
    brandDeep: Color(0xFF0E9E9A),
    brandSoft: Color(0xFF123E3D),
    brandInk: Color(0xFF8BF1E6),
    onBrand: Color(0xFF032B29),
    tileOff: Color(0xFF151C25),
    tileOn: Color(0xFFF4F6F9),
    tileOnInk: Color(0xFF0E1726),
    tileOnInkSoft: Color(0xFF5A6677),
    navBar: Color(0xF00D1218),
    glowA: Color(0x2E14B8A6),
    glowB: Color(0x247C5CFF),
    amber: Color(0xFFFFB547),
    orange: Color(0xFFFF7A45),
    blue: Color(0xFF60A5FA),
    violet: Color(0xFF9B87FF),
    cyan: Color(0xFF22D3EE),
    pink: Color(0xFFF472B6),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFFF6369),
    dangerSoft: Color(0xFF3A1518),
    dangerInk: Color(0xFFFFB4B6),
    shadow: Color(0x66000000),
  );

  /// Dégradé signature FlowIT (carte d'accueil, logo, écran de connexion).
  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        // Identique en clair et en sombre : c'est la signature de la marque.
        colors: const [Color(0xFF0B5563), Color(0xFF0E9E9A), Color(0xFF38D9C3)],
        stops: const [0, .6, 1],
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
