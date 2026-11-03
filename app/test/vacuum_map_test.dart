import 'package:flutter_test/flutter_test.dart';
import 'package:flowit_smart/ui/widgets/vacuum_map.dart';

void main() {
  test('pièces sans contour gardées (liste), pièces dessinables reconnues', () {
    final rooms = VacuumRoom.fromState({
      'rooms': [
        {'id': '0', 'name': 'Living room', 'pts': []},
        {
          'id': '1',
          'name': 'Kitchen',
          'pts': [
            [0, 0],
            [100, 0],
            [100, 100],
          ],
        },
        'n importe quoi',
      ],
    });
    expect(rooms.map((r) => r.id), ['0', '1']);
    expect(rooms[0].hasOutline, isFalse);
    expect(rooms[1].hasOutline, isTrue);
    expect(VacuumRoom.fromState(null), isEmpty);
  });
}
