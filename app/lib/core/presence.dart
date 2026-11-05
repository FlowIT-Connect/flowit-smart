import '../models/models.dart';

/// Journée d'un détecteur de présence, reconstruite à partir des arrivées / départs
/// notés par la passerelle (event_logs 'presence').
class PresenceDay {
  /// Périodes de présence (début, fin) entre [from] et maintenant.
  final List<(DateTime, DateTime)> segments;

  /// Nombre d'arrivées (passages) dans la période.
  final int arrivals;

  /// Durée totale de présence dans la période.
  final Duration total;

  /// Dernier changement connu (arrivée ou départ), null s'il n'y en a aucun dans la période.
  final DateTime? lastChange;

  /// Dernière arrivée connue dans la période.
  final DateTime? lastArrival;

  const PresenceDay({required this.segments, required this.arrivals, required this.total, this.lastChange, this.lastArrival});
}

/// [events] : du plus ancien au plus récent. [presentNow] : état actuel du capteur.
PresenceDay presenceDay(List<EventLog> events, {required bool presentNow, required DateTime from, required DateTime now}) {
  final list = events.where((e) => e.result == 'detected' || e.result == 'clear').where((e) => !e.createdAt.isBefore(from) && !e.createdAt.isAfter(now)).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  // État au début de la période : l'inverse du premier changement, sinon l'état actuel.
  var present = list.isEmpty ? presentNow : list.first.result == 'clear';
  var start = from;
  var arrivals = 0;
  DateTime? lastArrival;
  final segments = <(DateTime, DateTime)>[];
  for (final e in list) {
    final detected = e.result == 'detected';
    if (detected == present) continue; // doublon
    if (detected) {
      arrivals++;
      lastArrival = e.createdAt;
      start = e.createdAt;
    } else {
      segments.add((start, e.createdAt));
    }
    present = detected;
  }
  // Le dernier changement noté peut avoir quelques secondes de retard sur l'état affiché.
  if (present && presentNow) segments.add((start, now));
  final total = segments.fold(Duration.zero, (sum, s) => sum + s.$2.difference(s.$1));
  return PresenceDay(segments: segments, arrivals: arrivals, total: total, lastChange: list.isEmpty ? null : list.last.createdAt, lastArrival: lastArrival);
}
