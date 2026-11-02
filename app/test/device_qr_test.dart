import 'package:flutter_test/flutter_test.dart';
import 'package:flowit_smart/core/device_qr.dart';

void main() {
  test('QR Dahua : numéro de série, modèle, code de sécurité', () {
    final qr = DeviceQr.parse('{SN:9k00ab1cdef2345,DT:DH-H5A,SC:ABCD1234,NC:030}')!;
    expect(qr.manufacturer, 'Dahua');
    expect(qr.serial, '9K00AB1CDEF2345');
    expect(qr.model, 'DH-H5A');
    expect(qr.safetyCode, 'ABCD1234');
    expect(qr.driver, 'dahua');
  });

  test('variantes : sans accolades, points-virgules, retours à la ligne', () {
    expect(DeviceQr.parse('SN:9K00AB1CDEF2345;DT:IPC-HFW1230S')!.safetyCode, isNull);
    expect(DeviceQr.parse('SN:9K00AB1CDEF2345\nSC:XYZ98765')!.model, isNull);
  });

  test('QR étrangers refusés', () {
    expect(DeviceQr.parse(null), isNull);
    expect(DeviceQr.parse('https://example.com'), isNull);
    expect(DeviceQr.parse('SN:9K00AB1CDEF2345'), isNull, reason: 'numéro seul : trop vague');
    expect(DeviceQr.parse('{SN:ab;drop,DT:x}'), isNull);
  });
}
