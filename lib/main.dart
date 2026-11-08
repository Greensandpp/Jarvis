import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'app.dart';
import 'overlay/overlay_app.dart';
import 'services/calendar_reminder_service.dart';
import 'services/hermes_evolution_service.dart';
import 'services/jarvis_service.dart';
import 'services/jarvis_tools_service.dart';
import 'services/native_bridge_service.dart';
import 'services/screen_automation_service.dart';
import 'services/sentry_service.dart';
import 'services/settings_service.dart';
import 'services/task_executor.dart';
import 'services/telegram_service.dart';
import 'services/todo_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  NativeBridgeService.instance.init();

  final settings = SettingsService.instance;
  await settings.init();

  final executor = TaskExecutor.instance;
  await executor.init();

  await HermesEvolutionService.instance.init();
  await CalendarReminderService.instance.init();
  await TodoService.instance.init();

  if (settings.jarvisAlwaysOn) {
    JarvisService.instance.ensureAlwaysOnRunning();
  }

  _wireTelegram(executor, settings);
  _wireOverlayCommands(executor);

  runApp(const PrivateAgentApp());
}

/// Telegram bot -> task executor wiring.
void _wireTelegram(TaskExecutor executor, SettingsService settings) {
  final telegram = TelegramService.instance;

  telegram.onCommand = (chatId, text) async {
    final lower = text.toLowerCase();
    if (lower == '/status') {
      final running = executor.isBusy
          ? 'Running "${executor.currentGoal}" (step ${executor.step})'
          : 'Idle';
      final serviceOn =
          await ScreenAutomationService.instance.isServiceEnabled();
      await telegram.sendMessage(chatId,
          '📱 $running\nAccessibility service: ${serviceOn ? 'ON ✅' : 'OFF ❌'}');
      return;
    }
    if (lower == '/screenshot') {
      final shot =
          await ScreenAutomationService.instance.takeScreenshotBase64();
      if (shot == null) {
        await telegram.sendMessage(chatId, '⚠️ Screenshot failed.');
      } else {
        await telegram.sendScreenshot(chatId, shot);
      }
      return;
    }
    if (lower == '/cancel' || lower == '/stop') {
      if (executor.isBusy) {
        executor.cancel();
        await telegram.sendMessage(chatId, '⏹️ Cancelling current task…');
      } else {
        await telegram.sendMessage(chatId, 'Nothing is running.');
      }
      return;
    }
    if (executor.isBusy) {
      await telegram.sendMessage(
          chatId, '⏳ Busy with another task. Send /cancel to stop it.');
      return;
    }
    await telegram.sendMessage(chatId, '🚀 Starting task: $text');
    unawaited(executor.executeTask(text, telegramChatId: chatId));
  };

  // Push the final result (plus screenshot) back to the originating chat.
  executor.onTaskFinished = (chatId, entry) async {
    await telegram.sendMessage(chatId, telegram.formatTaskResult(entry));
    final shot = await ScreenAutomationService.instance.takeScreenshotBase64();
    if (shot != null) {
      await telegram.sendScreenshot(chatId, shot,
          caption: 'Final screen state');
    }
  };

  if (settings.telegramEnabled) {
    unawaited(telegram.start());
  }
}

bool _overlayTorchEnabled = false;

/// Commands coming from the floating overlay bubble/panel.
void _wireOverlayCommands(TaskExecutor executor) {
  FlutterOverlayWindow.overlayListener.listen((event) async {
    if (event is! String) return;
    Map<String, dynamic> decoded;
    try {
      final d = jsonDecode(event);
      if (d is! Map) return;
      decoded = d.map((k, v) => MapEntry('$k', v));
    } catch (_) {
      return;
    }
    if (decoded['type'] != 'command') return;
    switch (decoded['command']) {
      case 'request_shortcuts':
        await FlutterOverlayWindow.shareData(jsonEncode({
          'type': 'shortcuts_state',
          'items': SettingsService.instance.arcShortcuts,
        }));
        break;
      case 'save_shortcuts':
        final raw = decoded['items'];
        if (raw is List) {
          final allowed = <String>{
            'open_tradingview', 'toggle_torch', 'payment_safety',
            'summarize_screen',
          };
          final items = raw.whereType<String>()
              .where((item) => allowed.contains(item) ||
                  (item.startsWith('app:') &&
                   item.length > 4 && item.length <= 100 &&
                   !item.contains('\n')))
              .toList();
          await SettingsService.instance.setArcShortcuts(items);
          await FlutterOverlayWindow.shareData(jsonEncode({
            'type': 'shortcuts_state',
            'items': SettingsService.instance.arcShortcuts,
          }));
        }
        break;
      case 'open_quick_app':
        final app = decoded['app']?.toString().trim() ?? '';
        if (app.isNotEmpty && app.length <= 96) {
          unawaited(JarvisToolsService.instance.launchApp(app));
        }
        break;

      case 'start':
        final goal = decoded['goal']?.toString().trim() ?? '';
        if (goal.isNotEmpty && !executor.isBusy) {
          unawaited(executor.executeTask(goal));
        }
        break;
      case 'pause':
        executor.pause();
        break;
      case 'resume':
        executor.resume();
        break;
      case 'cancel':
        executor.cancel();
        break;
      case 'summarize_screen':
        unawaited(JarvisService.instance.processCommand('summarize this screen article'));
        break;
      case 'jarvis_command':
        final goal = decoded['goal']?.toString().trim() ?? '';
        if (goal.isNotEmpty) {
          unawaited(JarvisService.instance.processCommand(goal));
        }
        break;
      case 'open_tradingview':
        unawaited(JarvisToolsService.instance.launchApp('TradingView'));
        break;
      case 'toggle_torch':
        unawaited(JarvisToolsService.instance.setTorch(!_overlayTorchEnabled).then((ok) {
          if (ok) _overlayTorchEnabled = !_overlayTorchEnabled;
        }));
        break;
      case 'payment_safety':
        // Do not bypass the bank's app protection or silently revoke
        // Accessibility. Close the overlay and let the user turn off the
        // Accessibility permission in Android settings.
        unawaited(FlutterOverlayWindow.closeOverlay());
        unawaited(ScreenAutomationService.instance.openAccessibilitySettings());
        break;
      case 'toggle_sentry':
        unawaited(SentryService.instance.toggleSentry());
        break;
    }
  });
}

/// Entry point for the floating overlay window (separate Flutter engine
/// running in its own isolate). Must stay a top-level function annotated
/// with vm:entry-point.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayApp());
}
