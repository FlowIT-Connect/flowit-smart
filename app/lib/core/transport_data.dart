import 'transport.dart';

/// Données de transport embarquées, région par région.
///
/// Relevé du 2026-11-16. Ajouter une wilaya = ajouter une [TransportRegion] ici.
/// Les positions des gares et communes sont approximatives : elles servent seulement
/// à reconnaître la région et à proposer la gare la plus proche.
final transportRegions = <TransportRegion>[bejaia];

const _etusSite = TransportSource(name: 'ETUS Béjaïa (site officiel)', url: 'https://etusbejaia.dz/horaires/', date: '2026');
const _wikiBus = TransportSource(name: 'Wikipédia : Réseau de bus de Béjaïa', url: 'https://fr.wikipedia.org/wiki/R%C3%A9seau_de_bus_de_B%C3%A9ja%C3%AFa', date: 'non daté');
const _sntf = TransportSource(
  name: 'Horaires SNTF repris par Algérie Zoom',
  url: 'https://algeriezoom.com/train-alger-bejaia-horaires-sntf-officiels-et-gares-desservies/',
  date: '2026-06-27',
);
const _interWilaya2021 = TransportSource(
  name: 'Vitaminedz : horaires des lignes inter-wilayas de Béjaïa',
  url: 'https://www.vitaminedz.com/fr/Bejaia/horaires-des-services-de-transports-lignes-7136849-Articles-6-348-1.html',
  date: '2021-12-27',
);

TransportLine _etus(String code, String to, String first, String last, double km, int stops, {String? backFirst, String? backLast}) => TransportLine(
      id: 'bejaia-etus-$code',
      mode: TransportMode.urban,
      code: code,
      operator: 'ETUS Béjaïa',
      verified: true,
      lengthKm: km,
      stopCount: stops,
      source: _etusSite,
      services: [
        TransportService(from: 'Gare routière', to: to, first: first, last: last),
        if (backFirst != null) TransportService(from: to, to: 'Gare routière', first: backFirst, last: backLast),
      ],
    );

TransportLine _private(String code, String from, String to) => TransportLine(
      id: 'bejaia-p$code',
      mode: TransportMode.urban,
      code: code,
      operator: 'Transporteurs privés',
      source: _wikiBus,
      services: [TransportService(from: from, to: to)],
    );

TransportLine _car(String to, List<String> departures, {int? every, String? last, String? note}) => TransportLine(
      id: 'bejaia-car-${to.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '-')}',
      mode: TransportMode.interWilaya,
      code: to,
      operator: 'Transporteurs privés, gare routière de Béjaïa',
      source: _interWilaya2021,
      note: note,
      services: [TransportService(from: 'Béjaïa', to: to, departures: departures, every: every, last: last)],
    );

const _bejaiaStations = <TransportStop>[
  TransportStop('Béjaïa', lat: 36.7525, lon: 5.0700),
  TransportStop('Oued Ghir', lat: 36.7050, lon: 4.9700),
  TransportStop('El Kseur', lat: 36.6840, lon: 4.8520),
  TransportStop('Sidi Aïch', lat: 36.6120, lon: 4.6880),
  TransportStop('Tifrets', lat: 36.5850, lon: 4.6600),
  TransportStop('Ighzer Amokrane', lat: 36.5450, lon: 4.6000),
  TransportStop('Akbou', lat: 36.4580, lon: 4.5340),
  TransportStop('Laâgane', lat: 36.4200, lon: 4.4600),
  TransportStop('Tazmalt', lat: 36.3870, lon: 4.3990),
  TransportStop('Béni Mansour', lat: 36.3300, lon: 4.3400),
];

final bejaia = TransportRegion(
  id: 'bejaia',
  name: 'Béjaïa',
  lat: 36.7509,
  lon: 5.0567,
  radiusKm: 15,
  busStation: 'Gare routière de Béjaïa (dite « Quatre-Chemins »)',
  trainStations: _bejaiaStations,
  towns: const [
    TransportStop('Bejaia', lat: 36.7509, lon: 5.0567),
    TransportStop('Bougie', lat: 36.7509, lon: 5.0567),
    TransportStop('Tichy', lat: 36.6670, lon: 5.1630),
    TransportStop('Aokas', lat: 36.6350, lon: 5.2450),
    TransportStop('Souk El Tenine', lat: 36.6170, lon: 5.3330),
    TransportStop('Melbou', lat: 36.6370, lon: 5.3600),
    TransportStop('Kherrata', lat: 36.4930, lon: 5.2780),
    TransportStop('Darguina', lat: 36.5600, lon: 5.3100),
    TransportStop('Amizour', lat: 36.6400, lon: 4.9000),
    TransportStop('El Kseur', lat: 36.6840, lon: 4.8520),
    TransportStop('Oued Ghir', lat: 36.7050, lon: 4.9700),
    TransportStop('Toudja', lat: 36.7600, lon: 4.8800),
    TransportStop('Barbacha', lat: 36.5670, lon: 4.9700),
    TransportStop('Sidi Aich', lat: 36.6120, lon: 4.6880),
    TransportStop('Seddouk', lat: 36.5480, lon: 4.6860),
    TransportStop('Chemini', lat: 36.6000, lon: 4.6100),
    TransportStop('Adekar', lat: 36.6900, lon: 4.6700),
    TransportStop('Beni Maouche', lat: 36.4900, lon: 4.7600),
    TransportStop('Akbou', lat: 36.4580, lon: 4.5340),
    TransportStop('Ouzellaguen', lat: 36.5400, lon: 4.6000),
    TransportStop('Ighil Ali', lat: 36.3330, lon: 4.4500),
    TransportStop('Tazmalt', lat: 36.3870, lon: 4.3990),
    TransportStop('Boudjellil', lat: 36.3300, lon: 4.3400),
  ],
  lines: [
    // Bus urbains ETUS : premier et dernier départ, longueur et nombre d'arrêts publiés par l'ETUS.
    _etus('1', 'Adrar Oufarnou', '06:30', '18:20', 18, 6),
    _etus('2', 'Université', '05:50', '18:50', 11, 12),
    _etus('3', 'Boulevard Amirouche', '05:50', '18:50', 8.7, 10),
    _etus('4', 'Sidi Ahmed', '05:50', '18:30', 15, 14),
    _etus('5', 'Ighzer Ouzarif', '06:30', '20:00', 34, 11, backFirst: '05:10', backLast: '20:45'),
    // Lignes de quartier exploitées par des privés, au départ de la Porte Sarrasine (horaires non publiés).
    _private('01', 'Porte Sarrasine', 'Sidi Ahmed'),
    _private('02', 'Porte Sarrasine', 'Taghzouit'),
    _private('03', 'Porte Sarrasine', 'Tizi'),
    _private('04', 'Porte Sarrasine', 'Ihaddaden Ouffella'),
    _private('05', 'Porte Sarrasine', 'Dar Djbel'),
    _private('06', 'Porte Sarrasine', 'Boukhiama'),
    _private('07', 'Porte Sarrasine', 'Tazeboucht'),
    _private('08', 'Porte Sarrasine', 'Dar Nacer'),
    _private('09', 'Porte Sarrasine', 'Sidi Ouali'),
    _private('10', 'Porte Sarrasine', 'Aïn Skhoun'),
    _private('11', 'Porte Sarrasine', 'Ighil Ouazoug'),
    _private('12', 'Porte Sarrasine', 'Smina'),
    _private('13', 'Porte Sarrasine', 'Takeliat'),
    _private('14', 'Porte Sarrasine', 'Lazib Oumaamar'),
    _private('15', 'Porte Sarrasine', 'Cité Rabah Amkhoukh'),
    _private('16', 'Porte Sarrasine', 'Cité Saïd Belil'),
    _private('17', 'Porte Sarrasine', 'Tala Markha'),
    _private('18', 'Polyclinique Sidi Ahmed', 'Hôpital Frantz Fanon'),
    _private('19', 'Porte Sarrasine', 'Ihaddaden Ouadda'),

    // Cars inter-wilayas depuis la gare routière (relevé de 2021 : à reconfirmer au guichet).
    _car('Alger', const [
      '02:20', '02:40', '02:55', '03:30', '03:45', '04:00', '04:14', '04:30', '04:45', '05:00', '05:15', '05:30', '05:45', '06:00', '06:15', '06:30', '06:45',
      '07:00', '07:15', '07:30', '08:15', '09:45', '10:00', '10:30', '11:00', '11:15', '11:45', '12:00', '12:15', '12:45', '13:30', '13:45', '14:00', '15:10',
    ]),
    _car('Sétif', const ['04:30', '04:40', '04:50', '05:00'], every: 10, last: '18:30'),
    _car('Jijel', const ['05:45', '06:15', '06:35'], every: 10, last: '17:45'),
    _car('Tizi Ouzou', const ['06:00'], every: 15, last: '16:10', note: 'Environ 40 départs par jour, toutes les 10 à 20 min.'),
    _car('Bouira', const ['05:15', '05:30', '06:30', '06:45', '07:15', '09:15', '10:00', '10:30', '11:00', '11:30', '12:00', '13:30', '14:15', '14:45', '15:00', '16:00']),
    _car('Bordj Bou Arréridj', const ['12:45', '13:15']),
    _car('Constantine', const ['04:00']),
    _car('Oran', const ['18:00']),
    _car('Sidi Bel Abbès', const ['17:30']),
    _car('Hassi Messaoud', const ['14:30', '15:00', '15:30', '17:00', '17:30', '18:00'], note: 'Par Sétif (14h30, 15h00, 17h00) ou par Bouira (15h30, 17h30, 18h00).'),
    _car('Ouargla', const ['16:00', '16:30', '18:30']),
    _car('Ghardaïa', const ['16:00']),
    _car('Tamanrasset', const ['05:00']),

    // Train SNTF Béjaïa – Alger (Agha), un aller-retour par jour.
    const TransportLine(
      id: 'bejaia-sntf-alger',
      mode: TransportMode.train,
      code: 'Béjaïa – Alger',
      operator: 'SNTF',
      verified: true,
      source: _sntf,
      note: 'Réservation et prix : sntf.dz',
      services: [
        TransportService(from: 'Béjaïa', to: 'Alger (Agha)', departures: ['06:30'], stops: [
          TransportStop('Béjaïa', time: '06:30'),
          TransportStop('Oued Ghir', time: '06:42'),
          TransportStop('El Kseur', time: '06:54'),
          TransportStop('Sidi Aïch', time: '07:11'),
          TransportStop('Tifrets', time: '07:19'),
          TransportStop('Ighzer Amokrane', time: '07:25'),
          TransportStop('Akbou', time: '07:35'),
          TransportStop('Laâgane', time: '07:48'),
          TransportStop('Tazmalt', time: '07:54'),
          TransportStop('Béni Mansour', time: '08:03'),
          TransportStop('Aghnif', time: '08:15'),
          TransportStop('El Adjiba', time: '08:25'),
          TransportStop('Bouira', time: '08:53'),
          TransportStop('Draâ El Mizan', time: '09:23'),
          TransportStop('Lakhdaria', time: '09:41'),
          TransportStop('Boumerdès', time: '10:08'),
          TransportStop('Alger (Agha)', time: '10:39'),
        ]),
        TransportService(from: 'Alger (Agha)', to: 'Béjaïa', departures: ['14:33'], stops: [
          TransportStop('Alger (Agha)', time: '14:33'),
          TransportStop('Boumerdès', time: '15:03'),
          TransportStop('Lakhdaria', time: '15:30'),
          TransportStop('Draâ El Mizan', time: '15:51'),
          TransportStop('Bouira', time: '16:14'),
          TransportStop('Aghnif', time: '16:45'),
          TransportStop('Béni Mansour', time: '16:59'),
          TransportStop('Tazmalt', time: '17:13'),
          TransportStop('Laâgane', time: '17:20'),
          TransportStop('Akbou', time: '17:33'),
          TransportStop('Ighzer Amokrane', time: '17:44'),
          TransportStop('Tifrets', time: '17:50'),
          TransportStop('Sidi Aïch', time: '17:56'),
          TransportStop('El Kseur', time: '18:13'),
          TransportStop('Oued Ghir', time: '18:26'),
          TransportStop('Béjaïa', time: '18:38'),
        ]),
      ],
    ),
  ],
);
