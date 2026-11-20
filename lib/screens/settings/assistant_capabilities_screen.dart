import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../../core/build_profile.dart';
import '../../services/assistant_platform_service.dart';
import '../../widgets/jarvis_visual_mode_host.dart';

class AssistantCapabilitiesScreen extends StatefulWidget {
  const AssistantCapabilitiesScreen({super.key});
  @override
  State<AssistantCapabilitiesScreen> createState() =>
      _AssistantCapabilitiesScreenState();
}

class _AssistantCapabilitiesScreenState
    extends State<AssistantCapabilitiesScreen>
    with WidgetsBindingObserver {
  String status = 'Checking assistant role…';
  bool overlay = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    final role = await AssistantPlatformService.roleHeld();
    var active = false;
    if (BuildProfile.fullControl) {
      try {
        active = await FlutterOverlayWindow.isActive();
      } catch (_) {}
    }
    if (mounted)
      setState(() {
        status = role
            ? 'JARVIS is selected as assistant'
            : 'Assistant role not selected or unavailable';
        overlay = active;
      });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Android assistant')),
    body: ListView(
      children: [
        ListTile(
          title: Text(status),
          subtitle: const Text(
            'Android decides availability. Lock-screen hotword listening is not implemented.',
          ),
        ),
        ListTile(
          key: const ValueKey('request-assistant-role'),
          title: const Text('Choose JARVIS as assistant'),
          onTap: () async {
            final requested = await AssistantPlatformService.requestRole();
            if (mounted)
              setState(
                () => status = requested
                    ? 'Review the Android assistant chooser'
                    : 'Assistant role is unavailable on this device',
              );
          },
        ),
        SwitchListTile(
          key: const ValueKey('overlay-setting'),
          title: const Text('Floating overlay'),
          value: overlay,
          subtitle: Text(
            BuildProfile.fullControl
                ? 'Requires Android “display over other apps” permission.'
                : BuildProfile.unavailable('Floating overlay'),
          ),
          onChanged: !BuildProfile.fullControl
              ? null
              : (enabled) async {
                  try {
                    if (!enabled) {
                      await FlutterOverlayWindow.closeOverlay();
                    } else {
                      if (!await FlutterOverlayWindow.isPermissionGranted()) {
                        await FlutterOverlayWindow.requestPermission();
                        // Grant returns through Settings; require a fresh explicit toggle to start.
                        await refresh();
                        return;
                      }
                      await FlutterOverlayWindow.showOverlay(
                        height: 120,
                        width: 120,
                        enableDrag: true,
                        alignment: OverlayAlignment.centerRight,
                        flag: OverlayFlag.defaultFlag,
                        overlayTitle: 'JARVIS',
                        overlayContent: 'Floating assistant active',
                      );
                    }
                    await refresh();
                  } catch (_) {
                    if (mounted)
                      setState(
                        () => status =
                            'Overlay could not start. Check Android permissions.',
                      );
                  }
                },
        ),
        ListTile(
          title: const Text('Gemini Live settings'),
          subtitle: const Text('Requires a cloud token broker. PC can be off.'),
          onTap: () => showLiveVoiceSettings(
            context,
            JarvisVisualModeHostState.sharedLive,
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Typed and tap-to-talk requests use the phone directly. App launches and alarms use Android intents. '
            'Calls open a dialer; messages open drafts for you to send. Screen automation needs explicit approval '
            'and the Full Control permission. Payments, OTP and UPI PIN remain under your control. '
            'Gemini requires internet; offline shortcuts and installed local TTS remain available.',
          ),
        ),
      ],
    ),
  );
}
