import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';

/// Lieu de la maison pour la météo extérieure.
class WeatherPlace {
  final String name;
  final String? region;
  final double latitude;
  final double longitude;

  const WeatherPlace({required this.name, this.region, required this.latitude, required this.longitude});

  /// Lieu par défaut tant que l'utilisateur n'a pas choisi sa ville.
  static const algiers = WeatherPlace(name: 'Alger', region: 'Algérie', latitude: 36.7538, longitude: 3.0588);

  factory WeatherPlace.fromJson(Map<String, dynamic> j) => WeatherPlace(
        name: j['name'] as String,
        region: j['region'] as String?,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'name': name, 'region': region, 'latitude': latitude, 'longitude': longitude};

  String get label => region == null || region!.isEmpty ? name : '$name, $region';
}

/// Conditions actuelles à l'extérieur.
class WeatherReport {
  final double temperature;
  final double? apparentTemperature;
  final int? humidity;
  final double? windKmh;
  final double? min;
  final double? max;

  /// Code météo OMM (0 = ciel clair, 61 = pluie…).
  final int code;
  final bool isDay;
  final DateTime fetchedAt;

  const WeatherReport({
    required this.temperature,
    required this.code,
    required this.fetchedAt,
    this.apparentTemperature,
    this.humidity,
    this.windKmh,
    this.min,
    this.max,
    this.isDay = true,
  });

  /// Famille de conditions (clé de traduction `weather.<famille>`).
  String get condition => weatherCondition(code);
}

String weatherCondition(int code) => switch (code) {
      0 => 'clear',
      1 || 2 => 'partly',
      3 => 'cloudy',
      45 || 48 => 'fog',
      >= 51 && <= 57 => 'drizzle',
      >= 61 && <= 67 || >= 80 && <= 82 => 'rain',
      >= 71 && <= 77 || 85 || 86 => 'snow',
      >= 95 => 'storm',
      _ => 'cloudy',
    };

abstract class WeatherService {
  Future<WeatherReport> current(WeatherPlace place);
  Future<List<WeatherPlace>> search(String query, {String language = 'fr'});
}

/// Open-Meteo : sans clé ni compte, appelable depuis le navigateur.
///
/// L'offre gratuite est réservée à un usage non commercial : pour la commercialisation,
/// souscrire l'offre « API » et compiler avec --dart-define=WEATHER_API_KEY=… (les
/// requêtes passent alors par customer-api.open-meteo.com).
class OpenMeteoWeather implements WeatherService {
  OpenMeteoWeather({http.Client? client, this.apiKey = AppConfig.weatherApiKey}) : _client = client ?? http.Client();

  final http.Client _client;
  final String apiKey;

  bool get _paid => apiKey.isNotEmpty;

  Future<Map<String, dynamic>> _get(String host, String path, Map<String, String> query) async {
    final uri = Uri.https(_paid ? 'customer-$host' : host, path, {...query, if (_paid) 'apikey': apiKey});
    final res = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Météo indisponible (${res.statusCode})');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  @override
  Future<WeatherReport> current(WeatherPlace place) async {
    final j = await _get('api.open-meteo.com', '/v1/forecast', {
      'latitude': place.latitude.toStringAsFixed(4),
      'longitude': place.longitude.toStringAsFixed(4),
      'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m',
      'daily': 'temperature_2m_max,temperature_2m_min',
      'forecast_days': '1',
      'timezone': 'auto',
    });
    return parseOpenMeteo(j);
  }

  @override
  Future<List<WeatherPlace>> search(String query, {String language = 'fr'}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final j = await _get('geocoding-api.open-meteo.com', '/v1/search', {'name': q, 'count': '8', 'language': language, 'format': 'json'});
    return parseGeocoding(j);
  }
}

double? _num(dynamic v) => v is num ? v.toDouble() : null;
double? _first(dynamic list) => list is List && list.isNotEmpty ? _num(list.first) : null;

WeatherReport parseOpenMeteo(Map<String, dynamic> j) {
  final c = Map<String, dynamic>.from(j['current'] as Map);
  final daily = (j['daily'] as Map?) ?? const {};
  return WeatherReport(
    temperature: _num(c['temperature_2m'])!,
    apparentTemperature: _num(c['apparent_temperature']),
    humidity: _num(c['relative_humidity_2m'])?.round(),
    windKmh: _num(c['wind_speed_10m']),
    code: (_num(c['weather_code']) ?? 3).round(),
    isDay: c['is_day'] != 0,
    min: _first(daily['temperature_2m_min']),
    max: _first(daily['temperature_2m_max']),
    fetchedAt: DateTime.now(),
  );
}

List<WeatherPlace> parseGeocoding(Map<String, dynamic> j) => [
      for (final r in (j['results'] as List?) ?? const [])
        if (r is Map && r['latitude'] is num && r['longitude'] is num)
          WeatherPlace(
            name: r['name'].toString(),
            region: [r['admin1'], r['country']].whereType<String>().where((s) => s.isNotEmpty).join(', '),
            latitude: (r['latitude'] as num).toDouble(),
            longitude: (r['longitude'] as num).toDouble(),
          ),
    ];
