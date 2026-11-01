import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/notifications.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'device_detail.dart';

Future<void> openNotifications(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));

/// Cloche de la barre du haut, avec le nombre de notifications non lues.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final unread = state.unreadNotifications;
    final critical = state.notifications.any((n) => !n.isRead && n.priority == 'critical');
    return IconButton(
      key: const ValueKey('notification-bell'),
      tooltip: context.tr('notif.title'),
      onPressed: () => openNotifications(context),
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: critical ? priorityColor('critical') : context.flow.brand,
        textColor: Colors.white,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded),
      ),
    );
  }
}

/// Centre de notifications : non lues / historique, filtre par catégorie.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _unreadOnly = false;
  String? _category;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).loadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final f = context.flow;
    final all = state.notifications;
    final list = all.where((n) => (!_unreadOnly || !n.isRead) && (_category == null || n.category == _category)).toList();

    final items = <Widget>[];
    String? day;
    for (final n in list) {
      final d = _dayLabel(context, n.createdAt);
      if (d != day) {
        day = d;
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text(d, style: theme.textTheme.labelLarge?.copyWith(color: f.inkSoft, fontWeight: FontWeight.w800)),
        ));
      }
      items.add(_NotificationTile(key: ValueKey('notif-${n.id}'), notification: n));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.tr('notif.title')),
        actions: [
          IconButton(
            key: const ValueKey('notif-read-all'),
            tooltip: context.tr('notif.readAll'),
            onPressed: state.unreadNotifications == 0 ? null : state.markAllNotificationsRead,
            icon: const Icon(Icons.done_all_rounded),
          ),
          IconButton(
            key: const ValueKey('notif-settings'),
            tooltip: context.tr('notif.settings'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationSettingsScreen())),
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: state.loadNotifications,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.history_rounded),
                label: Text(context.tr('notif.history'), key: const ValueKey('notif-tab-all')),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.mark_email_unread_rounded),
                label: Text(context.tr('notif.unread', {'count': state.unreadNotifications}), key: const ValueKey('notif-tab-unread')),
              ),
            ],
            selected: {_unreadOnly},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _unreadOnly = v.first),
          ),
          const SizedBox(height: 12),
          Wrap(runSpacing: 8, children: [
            _filter(context, null, Icons.all_inclusive_rounded, context.tr('notif.cat.all')),
            for (final c in notificationCategories) _filter(context, c, categoryIcon(c), context.tr('notif.cat.$c')),
          ]),
          if (list.isEmpty)
            EmptyState(
              icon: _unreadOnly ? Icons.mark_email_read_rounded : Icons.notifications_none_rounded,
              title: context.tr(_unreadOnly ? 'notif.emptyUnread' : 'notif.empty'),
              message: context.tr('notif.emptyHint'),
            )
          else
            ...items,
        ]),
      ),
    );
  }

  Widget _filter(BuildContext context, String? category, IconData icon, String label) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: FilterChip(
          key: ValueKey('notif-filter-${category ?? 'all'}'),
          avatar: Icon(icon, size: 18),
          label: Text(label),
          selected: _category == category,
          showCheckmark: false,
          onSelected: (_) => setState(() => _category = category),
        ),
      );
}

String _two(int v) => v.toString().padLeft(2, '0');

String _dayLabel(BuildContext context, DateTime at) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return context.tr('notif.today');
  if (diff == 1) return context.tr('notif.yesterday');
  return '${_two(at.day)}/${_two(at.month)}/${at.year}';
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({super.key, required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final f = context.flow;
    final n = notification;
    final color = priorityColor(n.priority);
    final device = n.deviceId == null ? null : state.devices[n.deviceId];
    final time = '${_two(n.createdAt.hour)}:${_two(n.createdAt.minute)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey('dismiss-${n.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: AlignmentDirectional.centerEnd,
          padding: const EdgeInsetsDirectional.only(end: 24),
          decoration: BoxDecoration(color: priorityColor('critical').withValues(alpha: .25), borderRadius: BorderRadius.circular(22)),
          child: const Icon(Icons.delete_outline_rounded),
        ),
        onDismissed: (_) => state.deleteNotification(n),
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              state.markNotificationRead(n);
              if (device != null) showDeviceDetail(context, device.id);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IconBubble(icon: n.kind.icon, color: color, size: 42, glow: !n.isRead && n.priorityRank >= 2),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          state.notificationTitle(n),
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w800),
                        ),
                      ),
                      Text(time, style: theme.textTheme.labelSmall?.copyWith(color: f.inkSoft)),
                      if (!n.isRead) ...[
                        const SizedBox(width: 8),
                        Container(width: 9, height: 9, decoration: BoxDecoration(color: f.brand, shape: BoxShape.circle)),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(state.notificationBody(n), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      _Tag(icon: categoryIcon(n.category), label: context.tr('notif.cat.${n.category}'), color: f.inkSoft),
                      if (n.priorityRank >= 1) _Tag(icon: Icons.flag_rounded, label: context.tr('notif.priority.${n.priority}'), color: color),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Choix des notifications reçues et seuils de température.
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.notificationSettings;
    final theme = Theme.of(context);
    final f = context.flow;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(context.tr('notif.settings'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text(context.tr('notif.settingsHint'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft, height: 1.4)),
        ),
        for (final c in notificationCategories)
          SettingsGroup(
            title: context.tr('notif.cat.$c'),
            children: [
              for (final k in NotificationKind.all.where((k) => k.category == c))
                SwitchListTile(
                  key: ValueKey('notif-switch-${k.type}'),
                  secondary: TileIcon(k.icon, color: priorityColor(k.priority)),
                  title: Text(context.tr(k.labelKey)),
                  subtitle: Text(context.tr('notif.priority.${k.priority}')),
                  value: s.enabled(k.type),
                  onChanged: (on) => state.saveNotificationSettings(s.toggle(k.type, on)),
                ),
              if (c == 'climate' && s.enabled('temperature_abnormal')) ...[
                _ThresholdTile(
                  label: context.tr('notif.tempMax'),
                  value: s.tempMax,
                  min: 20,
                  max: 60,
                  onChanged: (v) => state.saveNotificationSettings(s.copyWith(tempMax: v)),
                ),
                _ThresholdTile(
                  label: context.tr('notif.tempMin'),
                  value: s.tempMin,
                  min: -20,
                  max: 18,
                  onChanged: (v) => state.saveNotificationSettings(s.copyWith(tempMin: v)),
                ),
              ],
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.phone_iphone_rounded, size: 18, color: f.inkSoft),
            const SizedBox(width: 8),
            Expanded(child: Text(context.tr('notif.pushSoon'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft, height: 1.4))),
          ]),
        ),
      ]),
    );
  }
}

/// Seuil réglé au curseur, enregistré quand on le relâche.
class _ThresholdTile extends StatefulWidget {
  const _ThresholdTile({required this.label, required this.value, required this.min, required this.max, required this.onChanged});

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  State<_ThresholdTile> createState() => _ThresholdTileState();
}

class _ThresholdTileState extends State<_ThresholdTile> {
  late double _v = widget.value;

  @override
  void didUpdateWidget(covariant _ThresholdTile old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _v = widget.value;
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
        child: Row(children: [
          const SizedBox(width: 50),
          Expanded(child: Text(widget.label)),
          SizedBox(
            width: 150,
            child: Slider(
              value: _v.clamp(widget.min, widget.max),
              min: widget.min,
              max: widget.max,
              divisions: (widget.max - widget.min).round(),
              label: '${_v.round()} °C',
              onChanged: (v) => setState(() => _v = v),
              onChangeEnd: widget.onChanged,
            ),
          ),
          SizedBox(width: 48, child: Text('${_v.round()} °C', textAlign: TextAlign.end)),
        ]),
      );
}
