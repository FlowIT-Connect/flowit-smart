import 'package:flowit_smart/core/qr/brand_catalog.dart';
import 'package:flowit_smart/core/qr/qr_recognition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const r = QrRecognizer();

  test('Matter : exemple de la spécification (vendeur de test, code masqué)', () {
    final q = r.recognize('MT:Y.K9042C00KA0648G00');
    expect(q.parser, 'matter');
    expect(q.type, QrCodeType.standard);
    expect(q.details['vendor_id'], '0xFFF1');
    expect(q.productId, '0x8000');
    expect(q.details['discriminator'], '3840');
    expect(q.secrets['passcode'], '20202021');
    expect(q.redactedPayload, isNot(contains('Y.K9')));
    expect(q.brand, isNull);
    expect(q.recognitionStatus, 'unsupported');
  });

  test('Dahua : étiquette réelle, code de sécurité masqué', () {
    final q = r.recognize('{SN:9K00AB1CDEF2345,DT:DH-H5A,SC:ABCD1234,NC:030}');
    expect(q.parser, 'dahua');
    expect(q.brand?.id, 'dahua');
    expect(q.brand?.route, BrandRoute.videoBox);
    expect(q.serial, '9K00AB1CDEF2345');
    expect(q.model, 'DH-H5A');
    expect(q.secrets['safety_code'], 'ABCD1234');
    expect(q.redactedPayload, isNot(contains('ABCD1234')));
  });

  test('Wi-Fi : marque devinée par le nom du réseau, mot de passe masqué', () {
    final q = r.recognize(r'WIFI:T:WPA;S:shellyplus1-a8032ab12345;P:motdepasse;;');
    expect(q.parser, 'wifi');
    expect(q.brand?.id, 'shelly');
    expect(q.brand?.support, BrandSupport.homeAssistant);
    expect(q.hasCredentials, isTrue);
    expect(q.redactedPayload, isNot(contains('motdepasse')));
  });

  test('Tuya : lien produit', () {
    final q = r.recognize('https://smartapp.tuya.com/s/p?p=abc123def&uuid=0123456789abcd&v=1.0');
    expect(q.parser, 'tuya');
    expect(q.brand?.route, BrandRoute.smartLife);
    expect(q.productId, 'abc123def');
    expect(q.serial, '0123456789abcd');
    expect(q.recognitionStatus, 'recognized');
  });

  test('HomeKit et Zigbee : formats standard, secrets masqués', () {
    final hk = r.recognize('X-HM://0023ISYWY1ABC');
    expect(hk.parser, 'homekit');
    expect(hk.redactedPayload, 'X-HM://****');
    final zb = r.recognize(r'Z:00124B0012345678$I:83FED3407A939723A5C639B26916D505C3B5');
    expect(zb.parser, 'zigbee');
    expect(zb.serial, '00124B0012345678');
    expect(zb.protocol, 'zigbee');
    expect(zb.redactedPayload, isNot(contains('83FED')));
  });

  test('lien web d\'un fabricant et étiquette clé:valeur', () {
    expect(r.recognize('https://www.aqara.com/product?sn=LUMI123456').brand?.id, 'aqara');
    final unknownSite = r.recognize('https://exemple.com/produit');
    expect(unknownSite.type, QrCodeType.url);
    expect(unknownSite.brand, isNull);
    final f = r.recognize('Brand: Sonoff; Model: BASICR2; SN: 1000ab12cd');
    expect(f.brand?.id, 'sonoff');
    expect(f.model, 'BASICR2');
    expect(f.serial, '1000ab12cd');
  });

  test('numéro de série seul, texte illisible', () {
    final s = r.recognize('SN2024A0012345');
    expect(s.type, QrCodeType.serial);
    expect(s.serial, 'SN2024A0012345');
    expect(s.brand, isNull);
    final u = r.recognize('Bonjour tout le monde !');
    expect(u.recognized, isFalse);
    expect(u.recognitionStatus, 'unknown');
  });

  test('le texte enregistré ne contient jamais de secret', () {
    expect(redactSecrets('user=admin&password=s3cret&sn=1'), 'user=admin&password=****&sn=1');
    expect(redactSecrets('{SN:1,SC:XYZ}'), '{SN:1,SC:****}');
  });
}
