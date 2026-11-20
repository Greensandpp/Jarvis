import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

/// Host side of `flutter drive`: saves screenshots taken on the emulator.
Future<void> main() => integrationDriver(
      onScreenshot: (name, bytes, [args]) async {
        final dir = Directory(Platform.environment['SHOT_DIR'] ?? 'drive-shots')..createSync(recursive: true);
        File('${dir.path}/$name.png').writeAsBytesSync(bytes);
        return true;
      },
    );
