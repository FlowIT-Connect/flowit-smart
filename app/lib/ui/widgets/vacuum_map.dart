import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import 'common.dart';

/// Pièce de la carte d'un robot aspirateur (coordonnées du robot, en millimètres).
class VacuumRoom {
  VacuumRoom(this.id, this.name, this.points);

  final String id;
  final String name;
  final List<Offset> points;

  static List<VacuumRoom> fromState(dynamic map) {
    final rooms = map is Map ? map['rooms'] : null;
    if (rooms is! List) return const [];
    final out = <VacuumRoom>[];
    for (final r in rooms) {
      if (r is! Map) continue;
      final pts = <Offset>[];
      for (final p in (r['pts'] as List?) ?? const []) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) pts.add(Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()));
      }
      // Pièce sans contour (certains robots yeedi) : gardée, proposée dans une liste.
      out.add(VacuumRoom('${r['id']}', '${r['name'] ?? r['id']}', pts.length >= 3 ? pts : const []));
    }
    return out;
  }

  bool get hasOutline => points.length >= 3;

  Offset get center {
    var x = 0.0, y = 0.0;
    for (final p in points) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / points.length, y / points.length);
  }
}

Offset? _position(dynamic map, String key) {
  final p = map is Map ? map[key] : null;
  return p is List && p.length >= 2 && p[0] is num && p[1] is num ? Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()) : null;
}

/// Noms de pièces par défaut du robot (en anglais) → clés de traduction.
const _roomNames = {
  'living room': 'living',
  'dining room': 'dining',
  'bedroom': 'bedroom',
  'study': 'study',
  'kitchen': 'kitchen',
  'bathroom': 'bathroom',
  'laundry': 'laundry',
  'lounge': 'lounge',
  'storeroom': 'storeroom',
  'kids room': 'kids',
  'sunroom': 'sunroom',
  'corridor': 'corridor',
  'balcony': 'balcony',
  'gym': 'gym',
};

String vacuumRoomName(BuildContext context, String name) {
  final key = _roomNames[name.trim().toLowerCase()];
  return key == null ? name : (context.tryTr('vacuum.room.$key') ?? name);
}

/// Passage entre les coordonnées du robot et celles de l'écran.
class _MapFrame {
  _MapFrame(this.bounds, this.size) {
    final s = math.min(size.width / bounds.width, size.height / bounds.height);
    scale = s.isFinite && s > 0 ? s : 1;
    offset = Offset((size.width - bounds.width * scale) / 2 - bounds.left * scale, (size.height - bounds.height * scale) / 2 - bounds.top * scale);
  }

  final Rect bounds;
  final Size size;
  late final double scale;
  late final Offset offset;

  Offset toScreen(Offset p) => p * scale + offset;
  Offset toMap(Offset s) => (s - offset) / scale;
}

Rect _bounds(List<VacuumRoom> rooms, List<Offset?> extra) {
  final pts = [for (final r in rooms) ...r.points, ...extra.whereType<Offset>()];
  if (pts.isEmpty) return const Rect.fromLTWH(-2000, -2000, 4000, 4000);
  var minX = pts.first.dx, maxX = minX, minY = pts.first.dy, maxY = minY;
  for (final p in pts) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  // Marge de 40 cm autour du logement, et 2 m au moins de côté.
  const pad = 400.0;
  final w = math.max(maxX - minX, 2000.0), h = math.max(maxY - minY, 2000.0);
  final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
  return Rect.fromCenter(center: Offset(cx, cy), width: w + 2 * pad, height: h + 2 * pad);
}

/// Carte du robot : nettoyage des pièces choisies (« Pièces ») ou d'une zone dessinée au doigt
/// (« Zone »), en une ou deux passes.
class VacuumMapPanel extends StatefulWidget {
  const VacuumMapPanel({
    super.key,
    required this.device,
    required this.cap,
    required this.enabled,
    required this.indicator,
    required this.showIndicator,
    required this.send,
  });

  final Device device;
  final Capability cap;
  final bool enabled;
  final Widget indicator;
  final bool showIndicator;
  final void Function(dynamic) send;

  @override
  State<VacuumMapPanel> createState() => _VacuumMapPanelState();
}

class _VacuumMapPanelState extends State<VacuumMapPanel> {
  String _mode = 'rooms';
  final _selected = <String>{};
  int _passes = 1;
  Offset? _zoneStart, _zoneEnd; // coordonnées du robot

  bool _offers(String m) => widget.cap.options.isEmpty || widget.cap.options.contains(m);

  @override
  void initState() {
    super.initState();
    if (!_offers('rooms')) _mode = 'zone';
  }

  Rect? get _zone => _zoneStart == null || _zoneEnd == null ? null : Rect.fromPoints(_zoneStart!, _zoneEnd!);

  bool get _zoneBigEnough => (_zone?.width ?? 0) >= 300 && (_zone?.height ?? 0) >= 300;

  void _start() {
    if (_mode == 'rooms') {
      widget.send({'mode': 'rooms', 'rooms': _selected.toList(), 'passes': _passes});
    } else {
      final z = _zone!;
      widget.send({
        'mode': 'zone',
        'zone': [z.left.round(), z.top.round(), z.right.round(), z.bottom.round()],
        'passes': _passes,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final map = widget.device.state['vacuum_map'];
    final rooms = VacuumRoom.fromState(map);
    final bot = _position(map, 'bot'), charger = _position(map, 'charger');
    _selected.removeWhere((id) => !rooms.any((r) => r.id == id));
    final hasMap = rooms.isNotEmpty;
    final drawn = rooms.where((r) => r.hasOutline).toList();
    // Robot qui ne donne pas le dessin des pièces : liste des pièces, pas de zone à dessiner.
    final listOnly = hasMap && drawn.isEmpty;
    if (listOnly) _mode = 'rooms';
    final bounds = _bounds(drawn, [bot, charger]);
    final ready = widget.enabled && (_mode == 'rooms' ? _selected.isNotEmpty : _zoneBigEnough);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const TileIcon(Icons.map_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Text(context.tr('cap.vacuum_clean'), style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (widget.showIndicator) widget.indicator,
            ],
          ),
          if (!hasMap) ...[
            const SizedBox(height: 10),
            Text(context.tr('vacuum.noMap'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: f.inkSoft)),
          ] else ...[
            const SizedBox(height: 12),
            if (!listOnly && _offers('rooms') && _offers('zone'))
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'rooms', icon: const Icon(Icons.meeting_room_rounded), label: Text(context.tr('vacuum.mode.rooms'))),
                  ButtonSegment(value: 'zone', icon: const Icon(Icons.crop_free_rounded), label: Text(context.tr('vacuum.mode.zone'))),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
            const SizedBox(height: 10),
            Text(
              context.tr(listOnly ? 'vacuum.hint.list' : (_mode == 'rooms' ? 'vacuum.hint.rooms' : 'vacuum.hint.zone')),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: f.inkSoft),
            ),
            const SizedBox(height: 8),
            if (listOnly)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in rooms)
                    FilterChip(
                      key: ValueKey('vacuum-room-${r.id}'),
                      avatar: const Icon(Icons.meeting_room_rounded, size: 18),
                      label: Text(vacuumRoomName(context, r.name)),
                      selected: _selected.contains(r.id),
                      onSelected: (on) => setState(() => on ? _selected.add(r.id) : _selected.remove(r.id)),
                    ),
                ],
              )
            else
              AspectRatio(
                aspectRatio: (bounds.width / bounds.height).clamp(.8, 1.6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: f.glass,
                      border: Border.all(color: f.glassBorder),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final frame = _MapFrame(bounds, box.biggest);
                        final names = {for (final r in drawn) r.id: vacuumRoomName(context, r.name)};
                        return GestureDetector(
                          key: const ValueKey('vacuum-map'),
                          behavior: HitTestBehavior.opaque,
                          onTapUp: _mode == 'rooms'
                              ? (e) {
                                  final p = frame.toMap(e.localPosition);
                                  for (final r in drawn.reversed) {
                                    if ((Path()..addPolygon(r.points, true)).contains(p)) {
                                      setState(() => _selected.contains(r.id) ? _selected.remove(r.id) : _selected.add(r.id));
                                      return;
                                    }
                                  }
                                }
                              : null,
                          onPanStart: _mode == 'zone'
                              ? (e) => setState(() {
                                  _zoneStart = frame.toMap(e.localPosition);
                                  _zoneEnd = _zoneStart;
                                })
                              : null,
                          onPanUpdate: _mode == 'zone' ? (e) => setState(() => _zoneEnd = frame.toMap(e.localPosition)) : null,
                          child: CustomPaint(
                            size: box.biggest,
                            painter: _MapPainter(
                              frame: frame,
                              rooms: drawn,
                              names: names,
                              selected: _mode == 'rooms' ? _selected : const {},
                              zone: _mode == 'zone' ? _zone : null,
                              bot: bot,
                              charger: charger,
                              colors: f,
                              textStyle: Theme.of(context).textTheme.labelMedium!,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(context.tr('vacuum.passes'), style: Theme.of(context).textTheme.bodyMedium),
                for (final n in const [1, 2])
                  ChoiceChip(label: Text(context.tr('vacuum.passes.$n')), selected: _passes == n, onSelected: (_) => setState(() => _passes = n)),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: ready ? _start : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                _mode == 'rooms'
                    ? (_selected.isEmpty
                          ? context.tr('vacuum.pickRooms')
                          : context.tr(_selected.length == 1 ? 'vacuum.cleanRoom' : 'vacuum.cleanRooms', {'n': _selected.length}))
                    : (_zoneBigEnough ? context.tr('vacuum.cleanZone') : context.tr('vacuum.drawZone')),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.frame,
    required this.rooms,
    required this.names,
    required this.selected,
    required this.zone,
    required this.bot,
    required this.charger,
    required this.colors,
    required this.textStyle,
  });

  final _MapFrame frame;
  final List<VacuumRoom> rooms;
  final Map<String, String> names;
  final Set<String> selected;
  final Rect? zone;
  final Offset? bot, charger;
  final FlowColors colors;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final palette = [colors.blue, colors.cyan, colors.violet, colors.amber, colors.pink, colors.orange];
    for (final (i, r) in rooms.indexed) {
      final path = Path()..addPolygon([for (final p in r.points) frame.toScreen(p)], true);
      final on = selected.contains(r.id);
      final base = palette[i % palette.length];
      canvas.drawPath(path, Paint()..color = on ? colors.brand.withValues(alpha: .55) : base.withValues(alpha: .22));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = on ? 2.4 : 1.2
          ..color = on ? colors.brand : base.withValues(alpha: .7),
      );
      final label = TextPainter(
        text: TextSpan(
          text: names[r.id] ?? r.name,
          style: textStyle.copyWith(color: colors.ink, fontWeight: on ? FontWeight.w700 : FontWeight.w500),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 110);
      label.paint(canvas, frame.toScreen(r.center) - Offset(label.width / 2, label.height / 2));
    }
    if (zone != null) {
      final rect = Rect.fromPoints(frame.toScreen(zone!.topLeft), frame.toScreen(zone!.bottomRight));
      canvas.drawRect(rect, Paint()..color = colors.brand.withValues(alpha: .25));
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = colors.brand,
      );
    }
    if (charger != null) {
      final c = frame.toScreen(charger!);
      canvas.drawCircle(c, 9, Paint()..color = colors.success);
      _icon(canvas, Icons.bolt_rounded, c, 13, Colors.white);
    }
    if (bot != null) {
      final c = frame.toScreen(bot!);
      canvas.drawCircle(c, 11, Paint()..color = colors.shadow.withValues(alpha: .25));
      canvas.drawCircle(c, 9, Paint()..color = colors.ink);
      _icon(canvas, Icons.cleaning_services_rounded, c, 11, colors.background);
    }
  }

  void _icon(Canvas canvas, IconData icon, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontSize: size, fontFamily: icon.fontFamily, package: icon.fontPackage, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_MapPainter old) => true;
}
