import 'messages.g.dart';

/// Dart wrapper around the native MCUmgr OS management group.
///
/// Provides device reset functionality via MCUmgr SMP protocol.
/// Requires the device to have SMP service enabled (CONFIG_ZSW_FW_UPDATE on ZSWatch).
class OsManager {
  OsManager._();

  static final OsManagerApi _api = OsManagerApi();

  /// Send a reset command to the device, causing it to reboot.
  ///
  /// [deviceId] - The BLE device remote ID (MAC address on Android, UUID on iOS).
  /// Throws a [PlatformException] if the SMP service is not available on the device.
  static Future<void> reset(String deviceId) async {
    await _api.reset(deviceId);
  }

  /// Kill the native OS manager instance, releasing the BLE transport.
  ///
  /// Call this after a reset or when done with the manager.
  static Future<void> kill(String deviceId) async {
    _api.kill(deviceId);
  }
}
