import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/glass.dart';
import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';

/// Mode « Organisation des appareils » : un appui long (≈ 550 ms) sur une tuile l'active et
/// commence le déplacement ; les tuiles bougent légèrement, un appui court n'ouvre plus rien,
/// et le bouton « Terminer » referme le mode. Fonctionne au doigt et à la souris.
class OrganizeController extends ChangeNotifier {
  bool _editing = false;
  String? _dragging;

  bool get editing => _editing;

  /// Identifiant de l'élément en cours de déplacement (null : aucun).
  String? get dragging => _dragging;

  void start() {
    if (_editing) return;
    _editing = true;
    HapticFeedback.mediumImpact();
    notifyListeners();
  }

  void stop() {
    if (!_editing && _dragging == null) return;
    _editing = false;
    _dragging = null;
    notifyListeners();
  }

  set dragging(String? id) {
    if (_dragging == id) return;
    _dragging = id;
    notifyListeners();
  }
}

class OrganizeScope extends InheritedNotifier<OrganizeController> {
  const OrganizeScope({super.key, required OrganizeController controller, required super.child}) : super(notifier: controller);

  static OrganizeController? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<OrganizeScope>()?.notifier;
}

/// Délai de l'appui long qui active l'organisation (évite les déplacements accidentels).
const organizeLongPress = Duration(milliseconds: 550);

/// Délai une fois le mode actif : le doigt peut encore faire défiler la page.
const organizeDragDelay = Duration(milliseconds: 160);

/// Grille de tuiles réorganisable par glisser-déposer (sliver).
///
/// Les autres tuiles glissent pour libérer la place ; le nouvel ordre est remis à
/// [onReorder] au lâcher. [onRemove] ajoute une petite croix en mode organisation.
class ReorderableTileGrid<T> extends StatefulWidget {
  const ReorderableTileGrid({
    super.key,
    required this.items,
    required this.idOf,
    required this.itemBuilder,
    required this.onReorder,
    this.onRemove,
    this.removeIcon = Icons.close_rounded,
    this.removeLabel,
    this.enabled = true,
    this.maxCrossAxisExtent = 210,
    this.mainAxisExtent = 164,
    this.spacing = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<T> items;
  final String Function(T) idOf;
  final Widget Function(BuildContext context, T item, bool editing) itemBuilder;
  final void Function(List<String> ids) onReorder;
  final void Function(T item)? onRemove;
  final IconData removeIcon;
  final String? removeLabel;

  /// false : grille ordinaire (pas d'appui long), par ex. pendant une recherche.
  final bool enabled;
  final double maxCrossAxisExtent;
  final double mainAxisExtent;
  final double spacing;
  final EdgeInsetsGeometry padding;

  @override
  State<ReorderableTileGrid<T>> createState() => _ReorderableTileGridState<T>();
}

class _ReorderableTileGridState<T> extends State<ReorderableTileGrid<T>> {
  late List<String> _order;
  late Map<String, T> _byId;
  String? _dragging;
  List<String>? _before;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ReorderableTileGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragging == null) {
      _sync();
    } else {
      // Pendant un déplacement : on garde l'ordre en cours, on suit seulement les ajouts/retraits.
      _byId = {for (final i in widget.items) widget.idOf(i): i};
      _order = [for (final id in _order) if (_byId.containsKey(id)) id, for (final id in _byId.keys) if (!_order.contains(id)) id];
    }
  }

  void _sync() {
    _byId = {for (final i in widget.items) widget.idOf(i): i};
    _order = [for (final i in widget.items) widget.idOf(i)];
  }

  void _moveOver(String dragged, String target) {
    final from = _order.indexOf(dragged);
    final to = _order.indexOf(target);
    if (from < 0 || to < 0 || from == to) return;
    setState(() {
      _order.removeAt(from);
      _order.insert(to, dragged);
    });
  }

  void _end(OrganizeController? controller) {
    final before = _before;
    _before = null;
    if (mounted) setState(() => _dragging = null);
    controller?.dragging = null;
    if (before != null && !_listEquals(before, _order) && _order.every(_byId.containsKey)) {
      widget.onReorder(List.of(_order));
    }
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final controller = OrganizeScope.maybeOf(context);
    final editing = controller?.editing ?? false;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return SliverPadding(
      padding: widget.padding,
      sliver: SliverToBoxAdapter(
        child: LayoutBuilder(builder: (context, box) {
          final s = widget.spacing;
          final cols = math.max(1, (box.maxWidth / (widget.maxCrossAxisExtent + s)).ceil());
          final w = (box.maxWidth - s * (cols - 1)) / cols;
          final h = widget.mainAxisExtent;
          final rows = (_order.length / cols).ceil();
          final height = rows == 0 ? 0.0 : rows * h + (rows - 1) * s;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          return SizedBox(
            height: height,
            child: Stack(clipBehavior: Clip.none, children: [
              for (var i = 0; i < _order.length; i++)
                AnimatedPositioned(
                  key: ValueKey('tile-${_order[i]}'),
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  left: rtl ? null : (i % cols) * (w + s),
                  right: rtl ? (i % cols) * (w + s) : null,
                  top: (i ~/ cols) * (h + s),
                  width: w,
                  height: h,
                  child: _tile(context, _order[i], w, h, editing, controller, i),
                ),
            ]),
          );
        }),
      ),
    );
  }

  Widget _tile(BuildContext context, String id, double w, double h, bool editing, OrganizeController? controller, int index) {
    final item = _byId[id] as T;
    final f = context.flow;
    final tile = widget.itemBuilder(context, item, editing);
    if (!widget.enabled || controller == null) return tile;
    final removable = editing && widget.onRemove != null;
    final body = Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(child: Wiggle(enabled: editing && _dragging != id, seed: index, child: tile)),
      if (removable)
        PositionedDirectional(
          top: -6,
          start: -6,
          child: Semantics(
            button: true,
            label: widget.removeLabel ?? context.tr('remove.title'),
            child: Material(
              key: ValueKey('remove-$id'),
              color: f.danger,
              shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: .9), width: 2)),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => widget.onRemove!(item),
                child: Padding(padding: const EdgeInsets.all(5), child: Icon(widget.removeIcon, size: 16, color: Colors.white)),
              ),
            ),
          ),
        ),
    ]);
    final draggable = LongPressDraggable<String>(
      data: id,
      delay: editing ? organizeDragDelay : organizeLongPress,
      hapticFeedbackOnStart: true,
      maxSimultaneousDrags: _dragging == null || _dragging == id ? 1 : 0,
      onDragStarted: () {
        controller.start();
        controller.dragging = id;
        setState(() {
          _dragging = id;
          _before = List.of(_order);
        });
      },
      onDragEnd: (_) => _end(controller),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: w,
          height: h,
          child: Transform.scale(scale: 1.06, child: Opacity(opacity: .94, child: widget.itemBuilder(context, item, true))),
        ),
      ),
      childWhenDragging: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          color: f.brand.withValues(alpha: .08),
          border: Border.all(color: f.brand.withValues(alpha: .45), width: 1.6),
        ),
      ),
      child: body,
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != id && _order.contains(d.data),
      onMove: (d) => _moveOver(d.data, id),
      builder: (context, _, _) => draggable,
    );
  }
}

/// Léger balancement des tuiles en mode organisation (coupé si l'utilisateur a demandé moins
/// d'animations).
class Wiggle extends StatefulWidget {
  const Wiggle({super.key, required this.enabled, required this.child, this.seed = 0});

  final bool enabled;
  final Widget child;
  final int seed;

  @override
  State<Wiggle> createState() => _WiggleState();
}

class _WiggleState extends State<Wiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: 260 + (widget.seed % 3) * 30));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(covariant Wiggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.enabled && !reduce) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else if (_c.isAnimating || _c.value != 0) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final sign = widget.seed.isEven ? 1.0 : -1.0;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => Transform.rotate(angle: sign * (_c.value - .5) * .022, child: child),
    );
  }
}

/// Cadre d'un écran organisable : affiche la barre « Organisation des appareils » en bas et,
/// pendant un déplacement d'appareil, les pièces où le déposer.
class OrganizeFrame extends StatelessWidget {
  const OrganizeFrame({super.key, required this.controller, required this.child, this.onDropToRoom, this.currentRoomId, this.bottom = 16});

  final OrganizeController controller;
  final Widget child;

  /// Déplacement vers une autre pièce (null : pas de cibles de pièces).
  final void Function(String deviceId, String? roomId)? onDropToRoom;

  /// Pièce affichée (pas proposée comme cible).
  final String? currentRoomId;
  final double bottom;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: controller, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    return OrganizeScope(
      controller: controller,
      child: PopScope(
        canPop: !controller.editing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.stop();
        },
        child: Stack(children: [
          Positioned.fill(child: child),
          if (controller.editing)
            Positioned(
              left: 12,
              right: 12,
              bottom: bottom,
              child: SafeArea(
                top: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (controller.dragging != null && onDropToRoom != null) ...[
                    _RoomTargets(currentRoomId: currentRoomId, onDrop: onDropToRoom!),
                    const SizedBox(height: 8),
                  ],
                  OrganizeBar(onDone: controller.stop),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class OrganizeBar extends StatelessWidget {
  const OrganizeBar({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    return GlassPanel(
      key: const ValueKey('organize-bar'),
      radius: 22,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
      child: Row(children: [
        Icon(Icons.open_with_rounded, color: f.brand),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(context.tr('organize.title'), style: TextStyle(fontWeight: FontWeight.w800, color: f.ink)),
            Text(context.tr('organize.hint'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: f.inkSoft)),
          ]),
        ),
        const SizedBox(width: 8),
        FilledButton(key: const ValueKey('organize-done'), onPressed: onDone, child: Text(context.tr('organize.done'))),
      ]),
    );
  }
}

class _RoomTargets extends StatelessWidget {
  const _RoomTargets({required this.currentRoomId, required this.onDrop});

  final String? currentRoomId;
  final void Function(String deviceId, String? roomId) onDrop;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final f = context.flow;
    final targets = <(String?, String, IconData)>[
      for (final r in state.rooms)
        if (r.id != currentRoomId) (r.id, r.name, roomIcon(r.icon)),
    ];
    if (targets.isEmpty) return const SizedBox.shrink();
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(context.tr('organize.dropRoom'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: f.inkSoft)),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (id, name, icon) in targets)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: DragTarget<String>(
                  onWillAcceptWithDetails: (d) => state.devices.containsKey(d.data),
                  onAcceptWithDetails: (d) => onDrop(d.data, id),
                  builder: (context, candidates, _) {
                    final hot = candidates.isNotEmpty;
                    return AnimatedContainer(
                      key: ValueKey('drop-room-${id ?? 'none'}'),
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: hot ? f.brand : f.chip,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: hot ? f.brand : f.cardBorder),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon, size: 18, color: hot ? f.onBrand : f.ink),
                        const SizedBox(width: 6),
                        Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: hot ? f.onBrand : f.ink)),
                      ]),
                    );
                  },
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
