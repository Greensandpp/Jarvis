import 'package:flutter/services.dart';

class AssistantPlatformService {
  static const channel = MethodChannel('greensoil/assistant');
  static Future<bool> roleHeld() async {
    try {
      return await channel.invokeMethod<bool>('roleHeld') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestRole() async {
    try {
      return await channel.invokeMethod<bool>('requestRole') ?? false;
    } catch (_) {
      return false;
    }
  }
}
