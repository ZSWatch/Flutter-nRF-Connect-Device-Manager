import 'messages.g.dart';

/// Result of a shell command execution via SMP.
class ShellCommandResult {
  final String output;
  final int returnCode;

  const ShellCommandResult({required this.output, required this.returnCode});

  bool get isSuccess => returnCode == 0;

  @override
  String toString() => 'ShellCommandResult(rc=$returnCode, output=$output)';
}

/// Dart wrapper around the native MCUmgr shell management group (SMP group 9).
///
/// Provides shell command execution over BLE via the SMP protocol.
/// Requires the device to have SMP service enabled and shell management
/// configured (CONFIG_MCUMGR_GRP_SHELL on Zephyr).
class ShellManager {
  ShellManager._();

  static final ShellManagerApi _api = ShellManagerApi();

  /// Execute a shell command on the device.
  ///
  /// [deviceId] - The BLE device remote ID (MAC address on Android, UUID on iOS).
  /// [command] - The shell command string (e.g. "kernel threads").
  /// Returns a [ShellCommandResult] with the command output and return code.
  ///
  /// Throws a [PlatformException] if the SMP service is not available.
  static Future<ShellCommandResult> execute(String deviceId, String command) async {
    final response = await _api.execute(deviceId, command);
    return ShellCommandResult(
      output: response.output,
      returnCode: response.returnCode.toInt(),
    );
  }

  /// Kill the native shell manager instance, releasing the BLE transport.
  ///
  /// Call this when done with shell operations or before disconnecting.
  static void kill(String deviceId) {
    _api.kill(deviceId);
  }
}
