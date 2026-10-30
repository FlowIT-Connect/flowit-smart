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

  /// Serrures à installer à portée (neuves ou remises à zéro), au fil de la recherche.
  Stream<NewLock> scanNewLocks();

  /// Installe la serrure et renvoie sa clé administrateur (lockData), à enregistrer
  /// aussitôt sur le compte TTLock par la passerelle.
  Future<String> initLock(NewLock lock);

  /// Remet la serrure en mode installation (si son enregistrement a échoué).
  Future<void> resetLock(String lockData);
}

/// Serrure TTLock en mode installation, vue en Bluetooth.
class NewLock {
  const NewLock({required this.name, required this.mac, required this.version, this.rssi = -100, this.battery});

  final String name;
  final String mac;
  final String version;
  final int rssi;
  final int? battery;
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
    await _ready();
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

  /// Bluetooth activé et autorisé, sinon [BleLockException].
  Future<void> _ready() async {
    if (!available) throw const BleLockException('failed', 'Bluetooth disponible seulement dans l\'app Android');
    final bluetooth = Completer<TTBluetoothState>();
    TTLock.getBluetoothState((s) => bluetooth.complete(s));
    final state = await bluetooth.future.timeout(const Duration(seconds: 5), onTimeout: () => TTBluetoothState.unknown);
    if (state == TTBluetoothState.turnOff) throw const BleLockException('bluetooth_off', 'Bluetooth désactivé');
    if (state == TTBluetoothState.unAuthorized) throw const BleLockException('permission', 'Autorisation Bluetooth refusée');
  }

  @override
  Stream<NewLock> scanNewLocks() {
    final out = StreamController<NewLock>();
    out.onListen = () async {
      try {
        await _ready();
      } on BleLockException catch (e) {
        out.addError(e);
        await out.close();
        return;
      }
      TTLock.startScanLock((m) {
        if (!m.isInited && !out.isClosed) {
          out.add(NewLock(name: m.lockName, mac: m.lockMac, version: m.lockVersion, rssi: m.rssi, battery: m.electricQuantity >= 0 ? m.electricQuantity : null));
        }
      });
    };
    out.onCancel = TTLock.stopScanLock;
    return out.stream;
  }

  @override
  Future<String> initLock(NewLock lock) async {
    await _ready();
    TTLock.stopScanLock();
    final done = Completer<String>();
    TTLock.initLock(
      {'lockMac': lock.mac, 'lockVersion': lock.version, 'isInited': false},
      (lockData) {
        if (!done.isCompleted) done.complete(lockData);
      },
      (error, message) {
        if (!done.isCompleted) done.completeError(BleLockException(_code(error), message));
      },
    );
    return done.future.timeout(const Duration(seconds: 40), onTimeout: () => throw const BleLockException('timeout', 'Serrure hors de portée'));
  }

  @override
  Future<void> resetLock(String lockData) async {
    await _ready();
    final done = Completer<void>();
    TTLock.resetLock(lockData, () {
      if (!done.isCompleted) done.complete();
    }, (error, message) {
      if (!done.isCompleted) done.completeError(BleLockException(_code(error), message));
    });
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

  @override
  Stream<NewLock> scanNewLocks() => Stream.error(const BleLockException('failed', 'Bluetooth indisponible'));

  @override
  Future<String> initLock(NewLock lock) => Future.error(const BleLockException('failed', 'Bluetooth indisponible'));

  @override
  Future<void> resetLock(String lockData) => Future.error(const BleLockException('failed', 'Bluetooth indisponible'));
}
