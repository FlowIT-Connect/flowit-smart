import 'package:flowit_smart/core/room_library.dart';
import 'package:flowit_smart/models/models.dart';
import 'package:flowit_smart/ui/widgets/room_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show pumpApp, signIn;

void main() {
  group('bibliothèque des pièces', () {
    test('10 catégories, 3 images chacune, clés valides', () {
      expect(RoomLibrary.categories, hasLength(10));
      for (final c in RoomLibrary.categories) {
        final images = RoomLibrary.imagesOf(c);
        expect(images, hasLength(3));
        for (final k in images) {
          expect(RoomLibrary.isValidKey(k), isTrue, reason: k);
          expect(RoomLibrary.categoryOfImage(k)?.key, c.key);
        }
      }
      expect(RoomLibrary.isValidKey('inconnu_1'), isFalse);
      expect(RoomLibrary.isValidKey('../salon_moderne_1'), isFalse);
    });

    test('image par défaut selon l\'icône de la pièce', () {
      const room = Room(id: 'r', homeId: 'h', name: 'Chambre', icon: 'bed');
      expect(room.libraryImage, 'chambre_parentale_1');
      expect(room.hasCustomImage, isFalse);
      expect(room.copyWith(imageKey: 'garage_2').libraryImage, 'garage_2');
      expect(room.copyWith(imageKey: 'garage_2').copyWith(clearImageKey: true).libraryImage, 'chambre_parentale_1');
    });

    test('cadrage borné et relu depuis la base', () {
      final fit = RoomImageFit.fromJson({'x': 4, 'y': -0.5, 'zoom': 0.2});
      expect(fit, const RoomImageFit(x: 1, y: -.5, zoom: 1));
      expect(RoomImageFit.fromJson(null), RoomImageFit.centered);
      expect(RoomImageFit.fromJson(fit.copyWith(zoom: 2.5).toJson()).zoom, 2.5);
    });
  });

  testWidgets('pièces en cartes photo, puis image choisie dans la bibliothèque', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Pièces').last);
    await tester.pumpAndSettle();

    expect(find.byType(RoomPhotoCard), findsWidgets);
    expect(find.text('Salon'), findsWidgets);

    await tester.tap(find.text('Salon').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('room-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Aperçu'), findsOneWidget);
    final editor = find.byType(ListView).first;
    await tester.dragUntilVisible(find.text('Bibliothèque Solea'), editor, const Offset(0, -200));
    await tester.pumpAndSettle();

    // Catégorie Garages, deuxième image.
    final chips = find.byType(ListView).at(1);
    await tester.dragUntilVisible(find.text('Garages'), chips, const Offset(-150, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garages'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.byKey(const ValueKey('lib-garage_2')), editor, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lib-garage_2')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();
    final salon = state.rooms.firstWhere((r) => r.name == 'Salon');
    expect(salon.imageKey, 'garage_2');
    expect(find.text('Pièce enregistrée.'), findsOneWidget);
  });

  testWidgets('accueil : section « Mes pièces » en cartes photo', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    final home = find.byType(CustomScrollView).first;
    await tester.dragUntilVisible(find.text('Mes pièces'), home, const Offset(0, -300));
    await tester.drag(home, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Mes pièces'), findsOneWidget);
    expect(find.byType(RoomPhotoCard), findsWidgets);
  });
}
