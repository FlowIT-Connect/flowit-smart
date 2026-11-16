import 'dart:math' as math;

import 'transport_data.dart';

/// Transports en commun de la région du logement : bus urbains, cars inter-wilayas, trains SNTF.
///
/// Les données sont embarquées dans l'app (voir [transportRegions]) : il n'existe pas de flux
/// ouvert pour les transports algériens. Chaque ligne dit d'où vient l'information, de quand
/// elle date, et si elle a été recoupée ([TransportLine.verified]).
enum TransportMode { urban, interWilaya, train }

/// Une heure de la journée, en minutes depuis minuit.
class DayTime implements Comparable<DayTime> {
  const DayTime(this.hour, this.minute);

  /// "06:30" ou "06h30".
  factory DayTime.parse(String s) {
    final p = s.toLowerCase().replaceAll('h', ':').split(':');
    return DayTime(int.parse(p[0]), p.length > 1 && p[1].isNotEmpty ? int.parse(p[1]) : 0);
  }

  final int hour;
  final int minute;

  int get minutes => hour * 60 + minute;

  static DayTime of(DateTime t) => DayTime(t.hour, t.minute);

  @override
  int compareTo(DayTime other) => minutes.compareTo(other.minutes);

  bool operator <=(DayTime o) => minutes <= o.minutes;
  bool operator >=(DayTime o) => minutes >= o.minutes;

  @override
  bool operator ==(Object other) => other is DayTime && other.minutes == minutes;

  @override
  int get hashCode => minutes;

  /// Affichage à l'algérienne : 06h30.
  String format() => '${hour.toString().padLeft(2, '0')}h${minute.toString().padLeft(2, '0')}';

  @override
  String toString() => format();
}

/// D'où vient l'information.
class TransportSource {
  const TransportSource({required this.name, required this.url, required this.date});

  final String name;
  final String url;

  /// Date de l'information telle que publiée (AAAA-MM-JJ, ou AAAA-MM / AAAA quand c'est tout ce qu'on sait).
  final String date;
}

/// Un arrêt ou une gare, avec l'heure de passage quand elle est connue.
class TransportStop {
  const TransportStop(this.name, {this.time, this.lat, this.lon});

  final String name;
  final String? time;
  final double? lat;
  final double? lon;

  DayTime? get dayTime => time == null ? null : DayTime.parse(time!);
}

/// Un service dans un sens : ses départs, ou son premier et dernier départ.
class TransportService {
  const TransportService({
    required this.from,
    required this.to,
    this.departures = const [],
    this.first,
    this.last,
    this.every,
    this.stops = const [],
  });

  final String from;
  final String to;

  /// Heures de départ connues (06:30…). Vide quand seuls le premier et le dernier sont publiés.
  final List<String> departures;
  final String? first;
  final String? last;

  /// Fréquence annoncée en minutes (« un départ toutes les 10 min »).
  final int? every;

  /// Arrêts dans l'ordre, avec heures de passage (trains).
  final List<TransportStop> stops;

  List<DayTime> get times => [for (final d in departures) DayTime.parse(d)]..sort();

  DayTime? get firstTime => first != null ? DayTime.parse(first!) : (times.isEmpty ? null : times.first);
  DayTime? get lastTime => last != null ? DayTime.parse(last!) : (times.isEmpty ? null : times.last);

  /// Prochain départ après [now] (null si plus aucun aujourd'hui, ou si on ne connaît que la plage).
  DayTime? nextDeparture(DayTime now) {
    for (final t in times) {
      if (t >= now) return t;
    }
    return null;
  }

  /// Le service roule-t-il à cette heure ? null si les horaires sont inconnus.
  bool? runningAt(DayTime now) {
    final a = firstTime, b = lastTime;
    if (a == null || b == null) return null;
    return now >= a && now <= b;
  }

  /// Heure de passage à un arrêt (trains).
  DayTime? timeAt(String stop) => stops.where((s) => s.name == stop).firstOrNull?.dayTime;
}

class TransportLine {
  const TransportLine({
    required this.id,
    required this.mode,
    required this.code,
    required this.operator,
    required this.services,
    required this.source,
    this.verified = false,
    this.lengthKm,
    this.stopCount,
    this.note,
  });

  final String id;
  final TransportMode mode;

  /// Numéro de ligne (« 1 »), ou destination pour un car inter-wilaya.
  final String code;
  final String operator;
  final List<TransportService> services;
  final TransportSource source;

  /// true quand l'information vient de l'exploitant ou de l'opérateur lui-même et date de moins d'un an.
  final bool verified;
  final double? lengthKm;
  final int? stopCount;

  /// Remarque affichée telle quelle (en français : nom propre ou précision de la source).
  final String? note;

  String get title => services.isEmpty ? code : '${services.first.from} → ${services.first.to}';
}

/// Une région couverte (une wilaya, pour commencer Béjaïa).
class TransportRegion {
  const TransportRegion({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.radiusKm,
    required this.lines,
    this.busStation,
    this.trainStations = const [],
    this.towns = const [],
  });

  final String id;
  final String name;
  final double lat;
  final double lon;

  /// Rayon autour de chaque commune listée dans lequel un logement est considéré comme dans la région.
  final double radiusKm;
  final List<TransportLine> lines;
  final String? busStation;
  final List<TransportStop> trainStations;

  /// Communes principales (position approximative) : la région est reconnue par la distance
  /// à l'une d'elles, ou par son nom dans le lieu saisi du logement.
  final List<TransportStop> towns;

  /// Distance du point le plus proche de la région (chef-lieu ou commune), en km.
  double distanceFrom(double lat, double lon) {
    var best = distanceKm(lat, lon, this.lat, this.lon);
    for (final t in towns) {
      if (t.lat == null || t.lon == null) continue;
      best = math.min(best, distanceKm(lat, lon, t.lat!, t.lon!));
    }
    return best;
  }

  List<TransportLine> byMode(TransportMode m) => [for (final l in lines) if (l.mode == m) l];

  /// Gare la plus proche d'une position (null sans gare ou sans position).
  TransportStop? nearestStation(double? lat, double? lon) {
    if (lat == null || lon == null) return null;
    TransportStop? best;
    var bestD = double.infinity;
    for (final s in trainStations) {
      if (s.lat == null || s.lon == null) continue;
      final d = distanceKm(lat, lon, s.lat!, s.lon!);
      if (d < bestD) {
        bestD = d;
        best = s;
      }
    }
    return best;
  }
}

/// Distance à vol d'oiseau, en km.
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

String _fold(String s) {
  const from = 'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ';
  const to = 'aaaeeeeiioouuucAAAEEEEIIOOUUUC';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), ' ').trim();
}

/// Région des transports pour une position, puis à défaut pour un nom de lieu (« Akbou, Béjaïa »).
TransportRegion? findTransportRegion({double? lat, double? lon, String? place, List<TransportRegion>? regions}) {
  final all = regions ?? transportRegions;
  if (lat != null && lon != null) {
    TransportRegion? best;
    var bestD = double.infinity;
    for (final r in all) {
      final d = r.distanceFrom(lat, lon);
      if (d <= r.radiusKm && d < bestD) {
        bestD = d;
        best = r;
      }
    }
    if (best != null) return best;
  }
  if (place != null && place.trim().isNotEmpty) {
    final words = ' ${_fold(place)} ';
    for (final r in all) {
      for (final n in [r.name, for (final t in r.towns) t.name]) {
        if (words.contains(' ${_fold(n)} ')) return r;
      }
    }
  }
  return null;
}
