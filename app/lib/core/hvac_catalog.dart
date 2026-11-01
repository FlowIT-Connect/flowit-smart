/// Solea HVAC Connect : bibliothèque des marques de climatiseurs et de chaudières, et des
/// façons de les relier à Solea.
///
/// Aucune intégration n'est codée marque par marque : chaque voie de connexion aboutit à
/// un adaptateur générique de la passerelle (Tuya, Home Assistant), qui expose les mêmes
/// capacités (mode, consigne, ventilation, ambiance…). Ajouter une marque = ajouter une ligne.
library;

/// Familles d'équipements.
enum HvacType { airConditioner, boiler, thermostat }

/// Voies de connexion, de la plus simple à la plus technique.
enum HvacRoute {
  /// Appareil Wi-Fi compatible Smart Life / Tuya : couplé dans Smart Life, repris par Solea.
  tuyaWifi,

  /// Télécommande infrarouge universelle Tuya : pour toute clim à télécommande.
  infrared,

  /// Application du fabricant reliée par une box Home Assistant (intégration officielle ou communautaire).
  homeAssistant,

  /// Thermostat connecté branché sur le bornier « thermostat d'ambiance » de la chaudière.
  roomThermostat,

  /// Passerelle OpenTherm (modulation, eau chaude, diagnostic) via Home Assistant.
  openTherm,

  /// Bus propriétaire de la chaudière (eBUS, EMS) lu par un adaptateur dédié via Home Assistant.
  boilerBus,

  /// Interface Modbus / RS485 posée par un installateur (clims professionnelles, VRF, chaudières).
  modbus,
}

/// Une marque et ce que l'on sait de ses voies de connexion.
class HvacBrand {
  const HvacBrand(
    this.name,
    this.types, {
    this.origin,
    this.app,
    this.haIntegration,
    this.officialHa = false,
    this.tuyaModels = false,
    this.openTherm = false,
    this.bus,
    this.modbus = false,
    this.algeria = false,
  });

  final String name;
  final Set<HvacType> types;
  final String? origin;

  /// Application du fabricant (pour reconnaître le Wi-Fi d'origine).
  final String? app;

  /// Nom de l'intégration Home Assistant qui gère l'application du fabricant.
  final String? haIntegration;

  /// Intégration incluse dans Home Assistant (sinon communautaire, via HACS).
  final bool officialHa;

  /// Certains modèles Wi-Fi s'appairent directement dans Smart Life.
  final bool tuyaModels;

  /// Bornier OpenTherm présent sur une partie des modèles.
  final bool openTherm;

  /// Bus propriétaire : 'eBUS' (groupe Vaillant) ou 'EMS' (groupe Bosch).
  final String? bus;

  /// Interface Modbus disponible (gammes professionnelles).
  final bool modbus;

  /// Distribuée en Algérie (mise en avant dans la liste).
  final bool algeria;
}

const _ac = {HvacType.airConditioner};
const _boiler = {HvacType.boiler};

/// Bibliothèque. Les voies indiquées dépendent du modèle exact : Solea le rappelle à l'écran
/// et le test de connexion affiche ce que l'appareil sait réellement faire.
const hvacBrands = <HvacBrand>[
  // ------------------------------------------------------------ Climatiseurs : Japon
  HvacBrand('Daikin', _ac, origin: 'Japon', app: 'Daikin Onecta', haIntegration: 'Daikin AC', officialHa: true, modbus: true, algeria: true),
  HvacBrand('Mitsubishi Electric', _ac, origin: 'Japon', app: 'MELCloud', haIntegration: 'MELCloud', officialHa: true, modbus: true, algeria: true),
  HvacBrand('Mitsubishi Heavy Industries', _ac, origin: 'Japon', app: 'Smart M-Air', modbus: true),
  HvacBrand('Panasonic', _ac, origin: 'Japon', app: 'Comfort Cloud', haIntegration: 'Panasonic Comfort Cloud', modbus: true),
  HvacBrand('Toshiba', _ac, origin: 'Japon', app: 'Toshiba Home AC Control', haIntegration: 'Toshiba AC', modbus: true),
  HvacBrand('Fujitsu', _ac, origin: 'Japon', app: 'FGLair', haIntegration: 'Fujitsu FGLair', officialHa: true, modbus: true),
  HvacBrand('General (Fujitsu General)', _ac, origin: 'Japon', app: 'FGLair', haIntegration: 'Fujitsu FGLair', officialHa: true, modbus: true),
  HvacBrand('Hitachi', _ac, origin: 'Japon', app: 'airCloud Home', haIntegration: 'Hitachi airCloud', modbus: true),
  HvacBrand('Hitachi Cooling & Heating', _ac, origin: 'Japon', app: 'airCloud Home', haIntegration: 'Hitachi airCloud', modbus: true),
  HvacBrand('Sharp', _ac, origin: 'Japon', app: 'Sharp Air'),
  // ------------------------------------------------------------ Corée
  HvacBrand('Samsung', _ac, origin: 'Corée du Sud', app: 'SmartThings', haIntegration: 'SmartThings', officialHa: true, modbus: true, algeria: true),
  HvacBrand('LG', _ac, origin: 'Corée du Sud', app: 'LG ThinQ', haIntegration: 'LG ThinQ', officialHa: true, modbus: true, algeria: true),
  HvacBrand('Winia', _ac, origin: 'Corée du Sud'),
  // ------------------------------------------------------------ Chine
  HvacBrand('Midea', _ac, origin: 'Chine', app: 'MSmartHome', haIntegration: 'Midea AC LAN', modbus: true, algeria: true),
  HvacBrand('Midea MDV', _ac, origin: 'Chine', app: 'MSmartHome', haIntegration: 'Midea AC LAN', modbus: true),
  HvacBrand('Gree', _ac, origin: 'Chine', app: 'Gree+', haIntegration: 'Gree Climate', officialHa: true, modbus: true, algeria: true),
  HvacBrand('TOSOT', _ac, origin: 'Chine', app: 'Gree+', haIntegration: 'Gree Climate', officialHa: true),
  HvacBrand('Haier', _ac, origin: 'Chine', app: 'hOn', haIntegration: 'Haier hOn', algeria: true),
  HvacBrand('Hisense', _ac, origin: 'Chine', app: 'ConnectLife', haIntegration: 'ConnectLife', algeria: true),
  HvacBrand('TCL', _ac, origin: 'Chine', app: 'TCL Home', algeria: true),
  HvacBrand('AUX', _ac, origin: 'Chine', app: 'AC Freedom', haIntegration: 'Broadlink AC'),
  HvacBrand('Chigo', _ac, origin: 'Chine'),
  HvacBrand('Changhong', _ac, origin: 'Chine'),
  HvacBrand('Kelvinator', _ac, origin: 'Chine'),
  // ------------------------------------------------------------ Algérie (assembleurs locaux)
  HvacBrand('Condor', _ac, origin: 'Algérie', algeria: true),
  HvacBrand('Brandt', _ac, origin: 'France / Algérie', algeria: true),
  HvacBrand('Iris', _ac, origin: 'Algérie', algeria: true),
  HvacBrand('Geant', _ac, origin: 'Algérie', algeria: true),
  HvacBrand('Raylan', _ac, origin: 'Algérie', algeria: true),
  // ------------------------------------------------------------ Amérique, Europe
  HvacBrand('Carrier', _ac, origin: 'États-Unis', modbus: true),
  HvacBrand('Trane', _ac, origin: 'États-Unis', modbus: true),
  HvacBrand('York', _ac, origin: 'États-Unis', modbus: true),
  HvacBrand('Lennox', _ac, origin: 'États-Unis', modbus: true),
  HvacBrand('Rheem', _ac, origin: 'États-Unis'),
  HvacBrand('Bosch', {HvacType.airConditioner, HvacType.boiler}, origin: 'Allemagne', app: 'Bosch HomeCom Easy', haIntegration: 'Bosch HomeCom', bus: 'EMS'),
  HvacBrand('Electrolux', _ac, origin: 'Suède'),
  HvacBrand('Olimpia Splendid', _ac, origin: 'Italie'),
  HvacBrand("De'Longhi", _ac, origin: 'Italie'),
  HvacBrand('Airwell', _ac, origin: 'France', algeria: true),
  HvacBrand('Atlantic', {HvacType.airConditioner, HvacType.boiler}, origin: 'France', app: 'Cozytouch', haIntegration: 'Overkiz (Cozytouch)', officialHa: true),

  // ------------------------------------------------------------ Chaudières : présentes en Algérie
  HvacBrand('Riello', _boiler, origin: 'Italie', openTherm: true, algeria: true),
  HvacBrand('Saunier Duval', _boiler, origin: 'France (Vaillant)', app: 'MiGo', haIntegration: 'myVAILLANT', bus: 'eBUS', algeria: true),
  HvacBrand('SIME', _boiler, origin: 'Italie', openTherm: true, algeria: true),
  HvacBrand('Baxi', _boiler, origin: 'Europe', app: 'Baxi', haIntegration: 'BDR Thermea', openTherm: true, algeria: true),
  HvacBrand('Junkers', _boiler, origin: 'Allemagne (Bosch)', app: 'Bosch HomeCom Easy', haIntegration: 'Bosch HomeCom', bus: 'EMS', algeria: true),
  HvacBrand('Buderus', _boiler, origin: 'Allemagne', app: 'MyBuderus', bus: 'EMS', algeria: true),
  HvacBrand('Viessmann', _boiler, origin: 'Allemagne', app: 'ViCare', haIntegration: 'Viessmann ViCare', officialHa: true, openTherm: true, modbus: true, algeria: true),
  HvacBrand('De Dietrich', _boiler, origin: 'France', app: 'Smart TC°', haIntegration: 'BDR Thermea', openTherm: true, algeria: true),
  HvacBrand('Ferroli', _boiler, origin: 'Italie', openTherm: true, algeria: true),
  HvacBrand('Chaffoteaux', _boiler, origin: 'France (Ariston)', app: 'Ariston NET', haIntegration: 'Ariston', algeria: true),
  HvacBrand('Ariston', _boiler, origin: 'Italie', app: 'Ariston NET', haIntegration: 'Ariston', algeria: true),
  HvacBrand('SIRA', _boiler, origin: 'Italie', openTherm: true, algeria: true),
  // ------------------------------------------------------------ Allemagne, Autriche
  HvacBrand('Vaillant', _boiler, origin: 'Allemagne', app: 'myVAILLANT', haIntegration: 'myVAILLANT', bus: 'eBUS'),
  HvacBrand('Bosch Thermotechnology', _boiler, origin: 'Allemagne', app: 'Bosch HomeCom Easy', haIntegration: 'Bosch HomeCom', bus: 'EMS'),
  HvacBrand('Wolf', _boiler, origin: 'Allemagne', app: 'Wolf Smartset', haIntegration: 'Wolf SmartSet', officialHa: true, modbus: true),
  HvacBrand('Weishaupt', _boiler, origin: 'Allemagne', modbus: true),
  HvacBrand('Hoval', _boiler, origin: 'Liechtenstein', modbus: true),
  HvacBrand('Worcester Bosch', _boiler, origin: 'Royaume-Uni (Bosch)', app: 'Bosch EasyControl', haIntegration: 'Bosch HomeCom', openTherm: true, bus: 'EMS'),
  // ------------------------------------------------------------ Italie
  HvacBrand('Immergas', _boiler, origin: 'Italie', app: 'Dominus', openTherm: true),
  HvacBrand('Beretta', _boiler, origin: 'Italie', openTherm: true),
  HvacBrand('Unical', _boiler, origin: 'Italie', openTherm: true),
  HvacBrand('Fondital', _boiler, origin: 'Italie', openTherm: true),
  HvacBrand('Lamborghini Caloreclima', _boiler, origin: 'Italie', openTherm: true),
  HvacBrand('Cointra', _boiler, origin: 'Espagne', openTherm: true),
  // ------------------------------------------------------------ France
  HvacBrand('Frisquet', _boiler, origin: 'France', app: 'Frisquet Connect'),
  HvacBrand('Groupe Atlantic', _boiler, origin: 'France', app: 'Cozytouch', haIntegration: 'Overkiz (Cozytouch)', officialHa: true),
  HvacBrand('Auer', _boiler, origin: 'France'),
  // ------------------------------------------------------------ Pays-Bas, Royaume-Uni
  HvacBrand('Remeha', _boiler, origin: 'Pays-Bas', app: 'Remeha Home', haIntegration: 'BDR Thermea', openTherm: true),
  HvacBrand('Ideal Heating', _boiler, origin: 'Royaume-Uni', openTherm: true),
  HvacBrand('Potterton', _boiler, origin: 'Royaume-Uni', openTherm: true),
  HvacBrand('Glow-worm', _boiler, origin: 'Royaume-Uni (Vaillant)', haIntegration: 'myVAILLANT', bus: 'eBUS'),
  HvacBrand('Protherm', _boiler, origin: 'Slovaquie (Vaillant)', haIntegration: 'myVAILLANT', bus: 'eBUS'),
  // ------------------------------------------------------------ Corée, Japon
  HvacBrand('Navien', _boiler, origin: 'Corée du Sud', app: 'NaviLink', haIntegration: 'NaviLink', openTherm: true),
  HvacBrand('KD Navien', _boiler, origin: 'Corée du Sud', app: 'NaviLink', haIntegration: 'NaviLink', openTherm: true),
  HvacBrand('Kiturami', _boiler, origin: 'Corée du Sud'),
  HvacBrand('Rinnai', _boiler, origin: 'Japon', app: 'Rinnai Control-R', haIntegration: 'Rinnai Control-R'),
  HvacBrand('Noritz', _boiler, origin: 'Japon'),
  // ------------------------------------------------------------ Amérique du Nord
  HvacBrand('A. O. Smith', _boiler, origin: 'États-Unis', app: 'iCOMM', haIntegration: 'A. O. Smith', officialHa: true),
  HvacBrand('Bradford White', _boiler, origin: 'États-Unis'),
  HvacBrand('Weil-McLain', _boiler, origin: 'États-Unis', modbus: true),
  HvacBrand('Lochinvar', _boiler, origin: 'États-Unis', modbus: true),
  HvacBrand('Burnham', _boiler, origin: 'États-Unis'),

  // ------------------------------------------------------------ Thermostats et têtes connectées
  HvacBrand('Netatmo', {HvacType.thermostat}, origin: 'France', app: 'Netatmo Energy', haIntegration: 'Netatmo', officialHa: true, openTherm: true),
  HvacBrand('tado°', {HvacType.thermostat}, origin: 'Allemagne', app: 'tado°', haIntegration: 'tado', officialHa: true),
  HvacBrand('Google Nest', {HvacType.thermostat}, origin: 'États-Unis', app: 'Google Home', haIntegration: 'Google Nest', officialHa: true, openTherm: true),
  HvacBrand('Honeywell Resideo', {HvacType.thermostat}, origin: 'États-Unis', app: 'Resideo', haIntegration: 'Honeywell Total Connect Comfort', officialHa: true, openTherm: true),
  HvacBrand('Moes / Beca (Tuya)', {HvacType.thermostat}, origin: 'Chine', app: 'Smart Life', tuyaModels: true, algeria: true),
];

/// Marques d'une famille, celles distribuées en Algérie d'abord puis par ordre alphabétique.
List<HvacBrand> brandsFor(HvacType type, {String query = ''}) {
  final q = query.trim().toLowerCase();
  final list = hvacBrands.where((b) => b.types.contains(type) && (q.isEmpty || b.name.toLowerCase().contains(q))).toList()
    ..sort((a, b) => a.algeria == b.algeria ? a.name.toLowerCase().compareTo(b.name.toLowerCase()) : (a.algeria ? -1 : 1));
  return list;
}

/// Voies de connexion possibles, la recommandée en premier.
///
/// [hasWifi] : l'appareil a le Wi-Fi d'origine (ou un module Wi-Fi du fabricant).
/// [brand] null = marque absente de la bibliothèque : voies universelles seulement.
List<HvacRoute> routesFor(HvacType type, HvacBrand? brand, {required bool hasWifi}) {
  final routes = <HvacRoute>[];
  switch (type) {
    case HvacType.airConditioner:
      if (hasWifi && (brand == null || brand.tuyaModels || brand.haIntegration == null)) routes.add(HvacRoute.tuyaWifi);
      if (hasWifi && brand?.haIntegration != null) routes.add(HvacRoute.homeAssistant);
      // La télécommande infrarouge marche avec toutes les clims, connectées ou non.
      routes.add(HvacRoute.infrared);
      if (brand?.modbus ?? false) routes.add(HvacRoute.modbus);
    case HvacType.boiler:
      if (hasWifi && brand?.haIntegration != null) routes.add(HvacRoute.homeAssistant);
      // Interface prévue par tous les fabricants : le contact « thermostat d'ambiance ».
      routes.add(HvacRoute.roomThermostat);
      if (brand == null || brand.openTherm) routes.add(HvacRoute.openTherm);
      if (brand?.bus != null) routes.add(HvacRoute.boilerBus);
      if (brand?.modbus ?? false) routes.add(HvacRoute.modbus);
    case HvacType.thermostat:
      if (brand == null || brand.tuyaModels) routes.add(HvacRoute.tuyaWifi);
      if (brand?.haIntegration != null) routes.add(HvacRoute.homeAssistant);
      if (routes.isEmpty) routes.add(HvacRoute.tuyaWifi);
  }
  return routes;
}

/// Voie qui se termine dans Smart Life (couplage dans l'app Tuya, puis repérage par Solea).
bool routeUsesSmartLife(HvacRoute r) => r == HvacRoute.tuyaWifi || r == HvacRoute.infrared || r == HvacRoute.roomThermostat;

/// Voie qui demande un installateur (câblage sur la chaudière ou interface professionnelle).
bool routeNeedsInstaller(HvacRoute r) => r == HvacRoute.openTherm || r == HvacRoute.boilerBus || r == HvacRoute.modbus;
