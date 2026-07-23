import 'package:flutter/services.dart';

/// Bridges to the native `AudioOutputPlugin`: whether a headphone-type output
/// (wired / Bluetooth / LE Audio / USB) is connected right now, so an alarm can
/// route only to it instead of the speaker.
class AudioOutput {
  static const _channel = MethodChannel('insulink/audio_output');

  /// True when headphones are connected. Best-effort — any platform error
  /// (unsupported OS, missing channel) reports false, so the alarm falls back to
  /// the speaker rather than going silent.
  Future<bool> headphonesConnected() async {
    try {
      return await _channel.invokeMethod<bool>('headphonesConnected') ?? false;
    } catch (_) {
      return false;
    }
  }
}
