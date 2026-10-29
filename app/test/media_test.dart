import 'dart:convert';
import 'dart:typed_data';

import 'package:flowit_smart/app.dart';
import 'package:flowit_smart/core/device_photos.dart';
import 'package:flowit_smart/core/icons.dart';
import 'package:flowit_smart/data/demo_backend.dart';
import 'package:flowit_smart/data/demo_camera.dart';
import 'package:flowit_smart/data/weather.dart';
import 'package:flowit_smart/models/models.dart';
import 'package:flowit_smart/state/app_state.dart';
import 'package:flowit_smart/ui/screens/device_detail.dart';
import 'package:flowit_smart/ui/widgets/camera_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeWeather implements WeatherService {
  final asked = <WeatherPlace>[];

  @override
  Future<WeatherReport> current(WeatherPlace place) async {
    asked.add(place);
    return WeatherReport(temperature: place.name == 'Oran' ? 29.6 : 24.2, code: 0, min: 18, max: 27, humidity: 55, fetchedAt: DateTime.now());
  }

  @override
  Future<List<WeatherPlace>> search(String query, {String language = 'fr'}) async => const [];
}

/// PNG 1×1 valide (photo prise par l'utilisateur dans les tests).
final tinyPng = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

Future<AppState> pumpApp(WidgetTester tester, {WeatherService? weather}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState(
    DemoBackend(latency: Duration.zero, confirmDelay: const Duration(milliseconds: 300), liveSensors: false),
    initialLocale: const Locale('fr'),
    weatherService: weather,
  );
  await tester.pumpWidget(FlowItApp(state: state));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(FilledButton).first);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return state;
}

Device byName(AppState s, String name) => s.devices.values.firstWhere((d) => d.name == name);

void main() {
  group('Météo', () {
    test('lecture de la réponse Open-Meteo et du géocodage', () {
      final r = parseOpenMeteo({
        'current': {'temperature_2m': 31.4, 'apparent_temperature': 33.0, 'relative_humidity_2m': 40, 'weather_code': 2, 'is_day': 1, 'wind_speed_10m': 12.5},
        'daily': {'temperature_2m_min': [21.0], 'temperature_2m_max': [33.2]},
      });
      expect(r.temperature, 31.4);
      expect(r.condition, 'partly');
      expect((r.min, r.max, r.humidity), (21.0, 33.2, 40));
      final places = parseGeocoding({
        'results': [
          {'name': 'Oran', 'admin1': 'Oran', 'country': 'Algérie', 'latitude': 35.69, 'longitude': -0.63},
          {'name': 'sans coordonnées'},
        ],
      });
      expect(places.single.label, 'Oran, Oran, Algérie');
      expect([0, 3, 45, 53, 63, 81, 73, 95].map(weatherCondition), ['clear', 'cloudy', 'fog', 'drizzle', 'rain', 'rain', 'snow', 'storm']);
    });

    test('offre gratuite par défaut, offre commerciale avec une clé', () async {
      final hosts = <String>[];
      Future<http.Response> handler(http.Request req) async {
        hosts.add('${req.url.host}${req.url.queryParameters.containsKey('apikey') ? ' +clé' : ''}');
        return http.Response(jsonEncode({'current': {'temperature_2m': 20, 'weather_code': 0, 'is_day': 1}}), 200);
      }

      await OpenMeteoWeather(client: MockClient(handler), apiKey: '').current(WeatherPlace.algiers);
      await OpenMeteoWeather(client: MockClient(handler), apiKey: 'k').current(WeatherPlace.algiers);
      expect(hosts, ['api.open-meteo.com', 'customer-api.open-meteo.com +clé']);
      final failing = OpenMeteoWeather(client: MockClient((_) async => http.Response('quota', 429)), apiKey: '');
      expect(failing.current(WeatherPlace.algiers), throwsException);
    });

    testWidgets('température extérieure sur l\'accueil, ville mémorisée par maison', (tester) async {
      final weather = FakeWeather();
      final state = await pumpApp(tester, weather: weather);
      await tester.pumpAndSettle();
      expect(find.text('Dehors 24°'), findsOneWidget);
      expect(find.text('Favoris'), findsOneWidget, reason: 'la météo ne repousse pas les favoris');
      await tester.tap(find.text('Dehors 24°'));
      await tester.pumpAndSettle();
      expect(find.text('Alger, Algérie'), findsOneWidget);
      expect(find.textContaining('Min 18°'), findsOneWidget);
      await tester.tap(find.text('Changer de ville'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oran'));
      await tester.pumpAndSettle();
      expect(state.weatherPlace.name, 'Oran');
      expect(state.weather?.temperature, 29.6);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('weather.place.${state.home!.id}'), contains('Oran'));
    });

    testWidgets('sans service météo : rien d\'affiché', (tester) async {
      await pumpApp(tester);
      expect(find.textContaining('Dehors'), findsNothing);
    });
  });

  group('Caméras', () {
    test('type d\'appareil : caméra, climatiseur ou thermostat', () async {
      final backend = DemoBackend(latency: Duration.zero, liveSensors: false);
      await backend.signIn('a@b.dz', 'x');
      final home = (await backend.listHomes()).first;
      final devices = await backend.listDevices(home.id);
      Device named(String n) => devices.firstWhere((d) => d.name == n);
      expect(deviceKind(named('Caméra entrée')), DeviceKind.camera);
      expect(named('Caméra entrée').readings.map((c) => c.key), ['motion'], reason: 'le flux caméra n\'est pas une mesure');
      expect(named('Caméra entrée').isUnsupported, isFalse);
      expect(deviceKind(named('Climatiseur salon')), DeviceKind.airConditioner);
      expect(deviceKind(named('Thermostat')), DeviceKind.climate);
      expect(devicePhotoKey(named('Climatiseur salon')), 'air_conditioner');
      expect(devicePhotoKey(named('Caméra entrée')), 'camera');
    });

    test('image simulée : BMP lisible', () {
      final bmp = demoCameraFrame(DateTime(2026), width: 32, height: 18);
      expect(String.fromCharCodes(bmp.sublist(0, 2)), 'BM');
      expect(bmp.length, 54 + 32 * 3 * 18);
    });

    testWidgets('fiche caméra : image en direct, flux arrêté à la fermeture', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Appareils').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'caméra');
      await tester.pumpAndSettle();
      expect(find.textContaining('Toucher pour voir'), findsOneWidget);
      await tester.tap(find.text('Caméra entrée'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byType(CameraLiveView), findsOneWidget);
      expect(find.text('EN DIRECT'), findsOneWidget);
      expect(find.descendant(of: find.byType(CameraLiveView), matching: find.byType(Image)), findsOneWidget);
      // Fermeture de la fiche : plus aucun minuteur ni flux actif.
      Navigator.of(tester.element(find.byType(CameraLiveView))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(CameraLiveView), findsNothing);
    });
  });

  group('Photos d\'appareils', () {
    tearDown(() => DevicePhotoCatalog.debugSet(const {}));

    test('type d\'image du sélecteur', () {
      expect(photoContentType('image/png', 'x'), 'image/png');
      expect(photoContentType(null, 'IMG_01.JPG'), 'image/jpeg');
      expect(photoContentType('application/pdf', 'doc.pdf'), isNull);
      expect(photoContentType(null, 'photo.heic'), isNull);
    });

    testWidgets('photo prise par l\'utilisateur : affichée sur la tuile, retour à la photo automatique', (tester) async {
      final state = await pumpApp(tester);
      final plafonnier = byName(state, 'Plafonnier');
      Finder tilePhoto() => find.descendant(of: find.ancestor(of: find.text('Plafonnier').first, matching: find.byType(Card)).first, matching: find.byType(Image));
      expect(tilePhoto(), findsNothing, reason: 'aucune photo livrée : icône');

      state.setDevicePhoto(plafonnier, Uint8List.fromList(tinyPng), 'image/png');
      await tester.pumpAndSettle();
      expect(state.devices[plafonnier.id]!.photoPath, startsWith('${plafonnier.homeId}/${plafonnier.id}-'));
      expect(tilePhoto(), findsOneWidget);
      expect(find.text('Photo enregistrée.'), findsOneWidget);

      state.clearDevicePhoto(state.devices[plafonnier.id]!);
      await tester.pumpAndSettle();
      expect(state.devices[plafonnier.id]!.photoPath, isNull);
      expect(tilePhoto(), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    test('format refusé', () async {
      final backend = DemoBackend(latency: Duration.zero, liveSensors: false);
      await backend.signIn('a@b.dz', 'x');
      final d = (await backend.listDevices((await backend.listHomes()).first.id)).first;
      expect(backend.setDevicePhoto(d, Uint8List(4), 'image/gif'), throwsA(isA<Object>()));
    });

    testWidgets('photo du type d\'appareil livrée avec l\'application', (tester) async {
      DevicePhotoCatalog.debugSet({'light': 'assets/devices/light.jpg'});
      await pumpApp(tester);
      final tile = find.ancestor(of: find.text('Plafonnier').first, matching: find.byType(Card)).first;
      expect(find.descendant(of: tile, matching: find.byType(Image)), findsOneWidget);
    });
  });
}
