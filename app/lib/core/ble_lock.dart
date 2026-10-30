import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ttlock_flutter/ttlock.dart';

/// Ouverture / fermeture d'une serrure TTLock en Bluetooth, devant la porte.
///
/// Seule l'app Android embarque le module Bluetooth de TTLock : sur le web, [available]
/// est faux et l'interface renvoie vers l'app Android.
abstract class BleLock {
  bool get available;

  /// [lockData] : clé Bluetooth de la serrure, fournie par le serveur (get_ble_key).
  /// Lève [BleLockException] avec un message lisible en cas d'échec.
  Future<void> control(String lockData, {required bool unlock});
}

class BleLockException implements Exception {
  const BleLockException(this.code, this.message);

  /// « bluetooth_off », « permission », « timeout », « out_of_range » ou « failed ».
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Module Bluetooth officiel TTLock (paquet ttlock_flutter), Android seulement.
class TTLockBle implements BleLock {
  const TTLockBle({this.timeout = const Duration(seconds: 25)});

  final Duration timeout;

  @override
  bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> control(String lockData, {required bool unlock}) async {
    if (!available) throw const BleLockException('failed', 'Bluetooth disponible seulement dans l\'app Android');
    final bluetooth = Completer<TTBluetoothState>();
    TTLock.getBluetoothState((s) => bluetooth.complete(s));
    final state = await bluetooth.future.timeout(const Duration(seconds: 5), onTimeout: () => TTBluetoothState.unknown);
    if (state == TTBluetoothState.turnOff) throw const BleLockException('bluetooth_off', 'Bluetooth désactivé');
    if (state == TTBluetoothState.unAuthorized) throw const BleLockException('permission', 'Autorisation Bluetooth refusée');

    final done = Completer<void>();
    TTLock.controlLock(
      lockData,
      unlock ? TTControlAction.unlock : TTControlAction.lock,
      (lockTime, electricQuantity, uniqueId, lockData) {
        if (!done.isCompleted) done.complete();
      },
      (error, message) {
        if (done.isCompleted) return;
        done.completeError(BleLockException(_code(error), message));
      },
    );
    await done.future.timeout(timeout, onTimeout: () => throw const BleLockException('timeout', 'Serrure hors de portée'));
  }

  static String _code(TTLockError e) => switch (e) {
        TTLockError.lockIsBusy || TTLockError.bluetoothConnectTimeout || TTLockError.bluetoothDisconnection => 'out_of_range',
        TTLockError.bluetoothOff => 'bluetooth_off',
        TTLockError.noPermission || TTLockError.eKeyExpired || TTLockError.eKeyInactive || TTLockError.invalidLockData => 'permission',
        _ => 'failed',
      };
}

/// Sans Bluetooth (web, tests).
class NoBleLock implements BleLock {
  const NoBleLock();

  @override
  bool get available => false;

  @override
  Future<void> control(String lockData, {required bool unlock}) =>
      Future.error(const BleLockException('failed', 'Bluetooth indisponible'));
}
