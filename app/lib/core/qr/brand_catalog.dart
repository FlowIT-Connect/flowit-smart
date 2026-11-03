/// Bibliothèque de compatibilité : les marques que Solea sait reconnaître et, pour chacune,
/// la vraie façon de la relier aujourd'hui.
///
/// Reconnaître une marque ≠ savoir la piloter. On distingue :
///   identification (le QR code dit qui est l'appareil),
///   authentification (compte ou code du fabricant),
///   appairage (l'appareil rejoint le réseau / le compte),
///   contrôle réel (la passerelle Solea lit son état et le commande).
/// Une marque n'est « prise en charge » que si les quatre étapes existent dans Solea.
library;

/// Niveau de prise en charge.
enum BrandSupport {
  /// Ajout et contrôle depuis Solea.
  supported,

  /// Possible seulement avec une box Home Assistant reliée à la passerelle Solea.
  homeAssistant,

  /// Pas encore pris en charge : ajout manuel ou signalement à l'administrateur.
  unsupported,
}

/// Parcours d'ajout ouvert dans Solea.
enum BrandRoute {
  /// Couplage dans Smart Life, repris tout de suite par la passerelle (Tuya).
  smartLife,

  /// Serrure TTLock installée en Bluetooth par le téléphone.
  ttlockBle,

  /// Caméra ou visiophone ajouté au boîtier vidéo (ONVIF / RTSP / Dahua).
  videoBox,

  /// Climatiseur ou chaudière (assistant Chauffage et clim).
  hvac,

  /// Aucun parcours dans Solea.
  none,
}

class Brand {
  const Brand(
    this.id,
    this.name, {
    required this.support,
    required this.route,
    this.hosts = const [],
    this.ssidPrefixes = const [],
    this.aliases = const [],
    this.matterVendors = const [],
    this.serialPrefixes = const [],
    this.category,
  });

  final String id;
  final String name;
  final BrandSupport support;
  final BrandRoute route;

  /// Noms de domaine présents dans les liens de ses QR codes.
  final List<String> hosts;

  /// Début du nom Wi-Fi émis par ses appareils en mode installation.
  final List<String> ssidPrefixes;
  final List<String> aliases;

  /// Identifiants fabricant Matter (Connectivity Standards Alliance).
  final List<int> matterVendors;

  /// Début de numéro de série propre à la marque.
  final List<String> serialPrefixes;

  /// Famille d'appareils principale (clé de traduction `brand.category.<category>`).
  final String? category;
}

class BrandCatalog {
  const BrandCatalog._();

  static const brands = <Brand>[
    Brand('tuya', 'Tuya', support: BrandSupport.supported, route: BrandRoute.smartLife,
        hosts: ['tuya.com', 'tuyaus.com', 'tuyaeu.com', 'tuyacn.com', 'tuyain.com'],
        ssidPrefixes: ['smartlife', 'sl-', 'tuya'], matterVendors: [0x125D], category: 'all'),
    Brand('smartlife', 'Smart Life', support: BrandSupport.supported, route: BrandRoute.smartLife,
        hosts: ['smartlife', 'smart-life'], aliases: ['smart life'], category: 'all'),
    Brand('ttlock', 'TTLock', support: BrandSupport.supported, route: BrandRoute.ttlockBle,
        hosts: ['ttlock.com', 'sciener.com'], aliases: ['sciener'], category: 'lock'),
    Brand('dahua', 'Dahua', support: BrandSupport.supported, route: BrandRoute.videoBox,
        hosts: ['dahuasecurity.com', 'imoulife.com'], aliases: ['imou'], category: 'camera'),
    Brand('hikvision', 'Hikvision', support: BrandSupport.supported, route: BrandRoute.videoBox,
        hosts: ['hikvision.com', 'hik-connect.com', 'ezviz'], category: 'camera'),
    Brand('reolink', 'Reolink', support: BrandSupport.supported, route: BrandRoute.videoBox,
        hosts: ['reolink.com'], category: 'camera'),
    Brand('daikin', 'Daikin', support: BrandSupport.supported, route: BrandRoute.hvac, hosts: ['daikin'], category: 'ac'),
    Brand('samsung', 'Samsung', support: BrandSupport.supported, route: BrandRoute.hvac,
        hosts: ['samsung.com', 'smartthings.com'], aliases: ['smartthings'], category: 'ac'),
    Brand('lg', 'LG', support: BrandSupport.supported, route: BrandRoute.hvac, hosts: ['lge.com', 'lgthinq.com', 'thinq'], aliases: ['lg electronics', 'thinq'], category: 'ac'),
    Brand('midea', 'Midea', support: BrandSupport.supported, route: BrandRoute.hvac, hosts: ['midea.com', 'msmarthome'], ssidPrefixes: ['net_ac_', 'midea'], category: 'ac'),
    Brand('gree', 'Gree', support: BrandSupport.supported, route: BrandRoute.hvac, hosts: ['gree.com', 'ewpe.com'], category: 'ac'),
    Brand('condor', 'Condor', support: BrandSupport.supported, route: BrandRoute.hvac, hosts: ['condor.dz', 'condor-electronics'], category: 'ac'),
    Brand('iris', 'IRIS', support: BrandSupport.supported, route: BrandRoute.hvac, hosts: ['iris.dz', 'iris-sat'], category: 'ac'),
    Brand('sonoff', 'Sonoff (eWeLink)', support: BrandSupport.homeAssistant, route: BrandRoute.none,
        hosts: ['sonoff.tech', 'itead.cc', 'ewelink.cc', 'coolkit.cc'], ssidPrefixes: ['itead-', 'ewelink', 'sonoff'], aliases: ['ewelink', 'itead'], category: 'all'),
    Brand('shelly', 'Shelly', support: BrandSupport.homeAssistant, route: BrandRoute.none,
        hosts: ['shelly.cloud', 'shelly.com'], ssidPrefixes: ['shelly'], category: 'all'),
    Brand('aqara', 'Aqara', support: BrandSupport.homeAssistant, route: BrandRoute.none,
        hosts: ['aqara.com', 'aqara.cn'], ssidPrefixes: ['aqara', 'lumi-'], aliases: ['lumi'], matterVendors: [0x115F], category: 'all'),
    Brand('xiaomi', 'Xiaomi', support: BrandSupport.homeAssistant, route: BrandRoute.none,
        hosts: ['mi.com', 'xiaomi.com', 'miot-spec.org'], ssidPrefixes: ['xiaomi', 'yeelink', 'chuangmi', 'zhimi', 'roborock'], aliases: ['mi home', 'mijia'], category: 'all'),
    Brand('hue', 'Philips Hue', support: BrandSupport.homeAssistant, route: BrandRoute.none,
        hosts: ['meethue.com', 'philips-hue.com', 'signify.com'], aliases: ['philips', 'signify', 'hue'], matterVendors: [0x100B], category: 'light'),
    Brand('eve', 'Eve', support: BrandSupport.homeAssistant, route: BrandRoute.none, hosts: ['evehome.com'], matterVendors: [0x130A], category: 'all'),
  ];

  static Brand? byId(String id) {
    for (final b in brands) {
      if (b.id == id) return b;
    }
    return null;
  }

  static Brand? byMatterVendor(int vendorId) {
    for (final b in brands) {
      if (b.matterVendors.contains(vendorId)) return b;
    }
    return null;
  }

  static Brand? byHost(String host) {
    final h = host.toLowerCase();
    for (final b in brands) {
      if (b.hosts.any((x) => h == x || h.endsWith('.$x') || (!x.contains('.') && h.contains(x)))) return b;
    }
    return null;
  }

  static Brand? bySsid(String ssid) {
    final s = ssid.toLowerCase();
    for (final b in brands) {
      if (b.ssidPrefixes.any(s.startsWith)) return b;
    }
    return null;
  }

  /// Marque citée dans un texte libre (nom ou alias, mot entier).
  static Brand? byText(String text) {
    final t = ' ${text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ')} ';
    if (t.trim().isEmpty) return null;
    for (final b in brands) {
      final names = [b.id, b.name.toLowerCase(), ...b.aliases];
      if (names.any((n) => t.contains(' ${n.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} '))) return b;
    }
    return null;
  }

  static Brand? bySerialPrefix(String serial) {
    final s = serial.toUpperCase();
    for (final b in brands) {
      if (b.serialPrefixes.any((p) => s.startsWith(p.toUpperCase()))) return b;
    }
    return null;
  }

  /// Recherche dans la bibliothèque (écran « Bibliothèque des marques »).
  static List<Brand> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return brands;
    return [for (final b in brands) if ('${b.name} ${b.aliases.join(' ')}'.toLowerCase().contains(q)) b];
  }
}
