import 'dart:async';

import 'package:flowit_smart/core/location.dart';
import 'package:flowit_smart/core/transport.dart';
import 'package:flowit_smart/core/transport_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show pumpApp, signIn;

class _FixedLocation implements LocationService {
  const _FixedLocation(this.lat, this.lon);
  final double lat;
  final double lon;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<LatLon?> current() async => (lat, lon);
  @override
  Stream<LatLon> watch() => const Stream.empty();
}

void main() {
  group('région', () {
    test('Béjaïa reconnue par la position, y compris dans la vallée et sur la côte', () {
      expect(findTransportRegion(lat: 36.7509, lon: 5.0567)?.id, 'bejaia');
      expect(findTransportRegion(lat: 36.46, lon: 4.53)?.id, 'bejaia', reason: 'Akbou');
      expect(findTransportRegion(lat: 36.64, lon: 5.25)?.id, 'bejaia', reason: 'Aokas');
      expect(findTransportRegion(lat: 36.39, lon: 4.40)?.id, 'bejaia', reason: 'Tazmalt');
    });

    test('les wilayas voisines ne sont pas prises pour Béjaïa', () {
      expect(findTransportRegion(lat: 36.7538, lon: 3.0588), isNull, reason: 'Alger');
      expect(findTransportRegion(lat: 36.82, lon: 5.77), isNull, reason: 'Jijel');
      expect(findTransportRegion(lat: 36.19, lon: 5.41), isNull, reason: 'Sétif');
      expect(findTransportRegion(lat: 36.71, lon: 4.05), isNull, reason: 'Tizi Ouzou');
    });

    test('reconnue par le nom du lieu, sans accents', () {
      expect(findTransportRegion(place: 'Bejaia, Algérie')?.id, 'bejaia');
      expect(findTransportRegion(place: 'Tichy')?.id, 'bejaia');
      expect(findTransportRegion(place: 'Oran, Algérie'), isNull);
    });
  });

  test('horaires : prochain départ, service en cours, gare la plus proche', () {
    final alger = bejaia.byMode(TransportMode.interWilaya).firstWhere((l) => l.code == 'Alger').services.first;
    expect(alger.nextDeparture(const DayTime(9, 0)), const DayTime(9, 45));
    expect(alger.nextDeparture(const DayTime(16, 0)), isNull);
    final ligne2 = bejaia.lines.firstWhere((l) => l.id == 'bejaia-etus-2').services.first;
    expect(ligne2.runningAt(const DayTime(12, 0)), isTrue);
    expect(ligne2.runningAt(const DayTime(22, 0)), isFalse);
    expect(bejaia.nearestStation(36.46, 4.53)?.name, 'Akbou');
    final train = bejaia.byMode(TransportMode.train).single.services.first;
    expect(train.timeAt('Akbou'), const DayTime(7, 35));
    expect(DayTime.parse('06h30').format(), '06h30');
  });

  test('chaque ligne a une source datée et des heures lisibles', () {
    for (final r in transportRegions) {
      for (final l in r.lines) {
        expect(l.source.url, startsWith('https://'), reason: l.id);
        for (final s in l.services) {
          s.times;
          s.firstTime;
          s.lastTime;
          for (final st in s.stops) {
            st.dayTime;
          }
        }
      }
      expect(r.lines.map((l) => l.id).toSet().length, r.lines.length, reason: 'identifiants uniques');
    }
  });

  testWidgets('maison à Alger : pas de données, puis « Me localiser » à Akbou affiche Béjaïa', (tester) async {
    await pumpApp(tester, location: const _FixedLocation(36.46, 4.53));
    await signIn(tester);
    await tester.tap(find.byKey(const ValueKey('transport-pill')).first);
    await tester.pumpAndSettle();
    expect(find.text('Pas encore de transports pour votre région'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('transport-locate-empty')));
    await tester.pumpAndSettle();
    expect(find.text('Autour de vous : Béjaïa'), findsOneWidget);
    expect(find.text('Gare routière → Université'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('transport-tab-inter')));
    await tester.pumpAndSettle();
    expect(find.text('Vers Alger'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('transport-tab-train')));
    await tester.pumpAndSettle();
    expect(find.text('Gare la plus proche : Akbou'), findsOneWidget);
    expect(find.text('Béjaïa → Alger (Agha)'), findsOneWidget);
    unawaited(Future<void>.value());
  });
}
