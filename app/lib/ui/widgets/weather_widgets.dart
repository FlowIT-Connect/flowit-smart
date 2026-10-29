import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/weather.dart';
import '../../state/app_state.dart';

IconData weatherIcon(WeatherReport w) => switch (w.condition) {
  'clear' => w.isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round,
  'partly' => w.isDay ? Icons.wb_cloudy_rounded : Icons.nights_stay_rounded,
  'cloudy' => Icons.cloud_rounded,
  'fog' => Icons.foggy,
  'drizzle' || 'rain' => Icons.water_drop_rounded,
  'snow' => Icons.ac_unit_rounded,
  'storm' => Icons.thunderstorm_rounded,
  _ => Icons.cloud_rounded,
};

String weatherLabel(BuildContext context, WeatherReport w) => context.tr(w.condition == 'clear' && !w.isDay ? 'weather.clearNight' : 'weather.${w.condition}');

String formatDegrees(double v) => '${v.round()}°';

/// Villes proposées sans recherche (fonctionne même si le géocodage est indisponible).
const algerianCities = [
  WeatherPlace.algiers,
  WeatherPlace(name: 'Oran', region: 'Algérie', latitude: 35.6971, longitude: -0.6308),
  WeatherPlace(name: 'Constantine', region: 'Algérie', latitude: 36.3650, longitude: 6.6147),
  WeatherPlace(name: 'Annaba', region: 'Algérie', latitude: 36.9000, longitude: 7.7667),
  WeatherPlace(name: 'Blida', region: 'Algérie', latitude: 36.4700, longitude: 2.8300),
  WeatherPlace(name: 'Sétif', region: 'Algérie', latitude: 36.1911, longitude: 5.4137),
  WeatherPlace(name: 'Tizi Ouzou', region: 'Algérie', latitude: 36.7169, longitude: 4.0497),
  WeatherPlace(name: 'Béjaïa', region: 'Algérie', latitude: 36.7509, longitude: 5.0567),
  WeatherPlace(name: 'Tlemcen', region: 'Algérie', latitude: 34.8783, longitude: -1.3150),
  WeatherPlace(name: 'Batna', region: 'Algérie', latitude: 35.5550, longitude: 6.1741),
  WeatherPlace(name: 'Ghardaïa', region: 'Algérie', latitude: 32.4900, longitude: 3.6700),
  WeatherPlace(name: 'Ouargla', region: 'Algérie', latitude: 31.9493, longitude: 5.3250),
];

/// Fiche météo : conditions détaillées et choix de la ville.
Future<void> showWeatherSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (_) => const _WeatherSheet(),
);

class _WeatherSheet extends StatelessWidget {
  const _WeatherSheet();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final f = context.flow;
    final theme = Theme.of(context);
    final w = state.weather;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('weather.title'), style: theme.textTheme.titleMedium?.copyWith(color: f.inkSoft)),
          const SizedBox(height: 4),
          Text(state.weatherPlace.label, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          if (w != null) ...[
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(gradient: f.brandGradient, shape: BoxShape.circle),
                  child: Icon(weatherIcon(w), color: Colors.white, size: 34),
                ),
                const SizedBox(width: 16),
                Text(formatDegrees(w.temperature), style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w300, height: 1)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(weatherLabel(context, w), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      if (w.apparentTemperature != null)
                        Text(context.tr('weather.feels', {'t': formatDegrees(w.apparentTemperature!)}), style: TextStyle(color: f.inkSoft)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (w.min != null && w.max != null)
                  Chip(
                    avatar: const Icon(Icons.thermostat_rounded, size: 18),
                    label: Text(context.tr('weather.minMax', {'min': formatDegrees(w.min!), 'max': formatDegrees(w.max!)})),
                  ),
                if (w.humidity != null)
                  Chip(avatar: const Icon(Icons.water_drop_rounded, size: 18), label: Text(context.tr('weather.humidity', {'n': w.humidity}))),
                if (w.windKmh != null)
                  Chip(avatar: const Icon(Icons.air_rounded, size: 18), label: Text(context.tr('weather.wind', {'n': w.windKmh!.round()}))),
              ],
            ),
            const SizedBox(height: 16),
          ],
          FilledButton.tonalIcon(
            onPressed: () async {
              final place = await showWeatherPlacePicker(context);
              if (place != null) await state.setWeatherPlace(place);
            },
            icon: const Icon(Icons.location_city_rounded),
            label: Text(context.tr('weather.changePlace')),
          ),
          const SizedBox(height: 12),
          Text(context.tr('weather.source'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkFaint)),
        ],
      ),
    );
  }
}

/// Choix de la ville : villes d'Algérie en un geste, ou recherche libre.
Future<WeatherPlace?> showWeatherPlacePicker(BuildContext context) => showDialog<WeatherPlace>(context: context, builder: (_) => const _PlacePicker());

class _PlacePicker extends StatefulWidget {
  const _PlacePicker();

  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  Timer? _debounce;
  String _query = '';
  List<WeatherPlace>? _results;
  bool _error = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    setState(() => _query = q.trim());
    if (_query.length < 2) {
      setState(() => _results = null);
      return;
    }
    final service = AppScope.read(context).weatherService;
    final language = Localizations.localeOf(context).languageCode;
    if (service == null) return;
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final asked = _query;
      List<WeatherPlace> found;
      var failed = false;
      try {
        found = await service.search(asked, language: language);
      } catch (_) {
        found = const [];
        failed = true;
      }
      if (!mounted || asked != _query) return;
      setState(() {
        _results = found;
        _error = failed;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final q = _query.toLowerCase();
    final local = algerianCities.where((c) => q.isEmpty || c.name.toLowerCase().contains(q)).toList();
    final remote = _results ?? const <WeatherPlace>[];
    return AlertDialog(
      title: Text(context.tr('weather.placeTitle')),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: context.tr('weather.search')),
              onChanged: _onChanged,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (q.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                      child: Text(
                        context.tr('weather.popular'),
                        style: TextStyle(color: f.inkSoft, fontWeight: FontWeight.w700),
                      ),
                    ),
                  for (final c in [...local, ...remote.where((r) => !local.any((l) => l.name == r.name && (l.latitude - r.latitude).abs() < .1))])
                    ListTile(
                      leading: const Icon(Icons.place_rounded),
                      title: Text(c.name),
                      subtitle: c.region == null ? null : Text(c.region!),
                      onTap: () => Navigator.pop(context, c),
                    ),
                  if (q.length >= 2 && _results != null && local.isEmpty && remote.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(context.tr(_error ? 'weather.searchError' : 'weather.noResult'), style: TextStyle(color: f.inkSoft)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel')))],
    );
  }
}
