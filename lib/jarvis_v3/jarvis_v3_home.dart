import 'package:flutter/material.dart';

import '../services/jarvis_service.dart';
import '../services/settings_service.dart';
import '../services/task_executor.dart';
import '../services/voice_service.dart';
import '../widgets/jarvis_visual_mode_host.dart';
import 'assistant_activity.dart';
import 'chat_auto_hide.dart';
import 'chat_interface_settings.dart';
import 'conversation_store.dart';
import 'neon_conversation.dart';
import 'neon_dock.dart';
import 'neon_theme.dart';
import 'visual_mode_store.dart';
import 'holographic_stage.dart';
import 'hologram_theme_store.dart';

/// Everything the main screen reads from, or sends to, the real services.
/// Tests pass doubles; production uses [JarvisV3Bindings.live].
class JarvisV3Bindings {
  JarvisV3Bindings({
    required this.source,
    required this.activitySignals,
    required this.conversationSignals,
    required this.soundLevel,
    required this.toggleMic,
    required this.onCommand,
    required this.aiVerified,
    required this.aiErrorKind,
    required this.standbyMic,
  });

  factory JarvisV3Bindings.live({required ValueChanged<String> onCommand}) {
    final j = JarvisService.instance;
    final v = VoiceService.instance;
    final e = TaskExecutor.instance;
    final s = SettingsService.instance;
    return JarvisV3Bindings(
      source: Listenable.merge([j, v.listeningNotifier, v.isSpeaking, v.completedSpeech, e, s]),
      activitySignals: () => ActivitySignals(
        phase: j.phase,
        completedSerial: v.completedSpeech.value,
        micCapturing: v.listeningNotifier.value,
        executorRunning: e.isBusy,
        chatBusy: e.isChatBusy,
        aiConfigured: s.apiKey.isNotEmpty || s.provider == 'ollama',
        errorStatus: j.statusMessage.startsWith('AI ERROR'),
      ),
      conversationSignals: () => ConversationSignals(
        phase: j.phase,
        userText: j.lastUserSpeech,
        jarvisText: j.lastJarvisSpeech,
        status: j.statusMessage,
        awaitingConfirmation: j.isAwaitingProactiveConfirmation,
      ),
      soundLevel: () => j.soundLevel.clamp(0.0, 1.0),
      toggleMic: j.toggleListening,
      onCommand: onCommand,
      aiVerified: () => s.aiVerified,
      aiErrorKind: () => s.aiLastErrorKind,
      standbyMic: () =>
          v.listeningNotifier.value && j.phase == JarvisPhase.idle,
    );
  }

  final Listenable source;
  final ActivitySignals Function() activitySignals;
  final ConversationSignals Function() conversationSignals;
  final double Function() soundLevel;
  final Future<void> Function() toggleMic;
  final ValueChanged<String> onCommand;
  final bool Function() aiVerified;
  final String Function() aiErrorKind;

  /// The recogniser is on in wake-word standby although nothing is shown as
  /// LISTENING; the header says so rather than hiding an open microphone.
  final bool Function() standbyMic;
}

/// Small status shown in the header, derived only from real state.
({String label, Color color}) headerStatus({
  required AssistantActivity activity,
  required bool aiVerified,
  required String aiErrorKind,
  required bool standbyMic,
}) {
  switch (activity) {
    case AssistantActivity.disconnected:
      return (label: 'CONFIGURATION MISSING', color: NeonColors.amber);
    case AssistantActivity.error:
      return (label: 'ERROR', color: NeonColors.error);
    case AssistantActivity.idle:
      if (aiErrorKind.isNotEmpty) {
        final label = switch (aiErrorKind) {
          'auth' => 'AUTH REQUIRED',
          'noKey' => 'CONFIGURATION MISSING',
          'dns' || 'connect' || 'timeout' => 'OFFLINE',
          _ => 'ERROR · ${aiErrorKind.toUpperCase()}',
        };
        return (label: label, color: NeonColors.error);
      }
      final base = aiVerified ? 'CONNECTED' : 'NOT VERIFIED';
      return (
        label: standbyMic ? '$base · MIC STANDBY' : base,
        color: aiVerified ? const Color(0xFF5CFF9D) : NeonColors.amber,
      );
    case AssistantActivity.listening:
      return (label: 'LISTENING', color: NeonColors.cyan);
    default:
      return (label: activity.label, color: NeonColors.gold);
  }
}

class JarvisV3Home extends StatefulWidget {
  const JarvisV3Home({
    super.key,
    required this.bindings,
    required this.onOpenMenu,
    required this.onOpenSettings,
    this.onLongPressTitle,
    this.settings,
    this.playIntro,
    this.modeStore,
  });

  final JarvisV3Bindings bindings;
  final VoidCallback onOpenMenu;
  final VoidCallback onOpenSettings;
  final VoidCallback? onLongPressTitle;
  final ChatInterfaceSettings? settings;

  /// Defaults to "once per app launch, when enabled".
  final bool? playIntro;
  final VisualModeStore? modeStore;

  static bool _introPlayedThisLaunch = false;

  @override
  State<JarvisV3Home> createState() => JarvisV3HomeState();
}

class JarvisV3HomeState extends State<JarvisV3Home>
    with WidgetsBindingObserver {
  late final ChatInterfaceSettings _settings;
  late final VisualModeStore _modes;
  late final AssistantActivityEngine activity;
  late final ConversationStore conversation;
  late final ChatAutoHideController autoHide;
  late final AiraPhaseBinding _aira;
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _stageKey = GlobalKey<HolographicStageState>();
  late bool _introRunning;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settings = widget.settings ?? ChatInterfaceSettings.instance;
    _modes = widget.modeStore ?? VisualModeStore.instance;
    final b = widget.bindings;
    activity = AssistantActivityEngine(
      source: b.source,
      read: b.activitySignals,
    );
    conversation = ConversationStore(
      source: b.source,
      read: b.conversationSignals,
      persist: () => _settings.saveHistory,
    );
    autoHide = ChatAutoHideController(
      enabled: _settings.autoHide,
      delay: _settings.delay,
      showWhileSpeaking: _settings.showWhileSpeaking,
    );
    _aira = AiraPhaseBinding(b.source, () => b.activitySignals().phase);
    activity.addListener(_onActivity);
    conversation.addListener(_onConversation);
    _settings.addListener(_onSettings);
    _focus.addListener(_onFocus);
    _introRunning =
        widget.playIntro ??
        (_settings.introEnabled &&
            !_settings.reduceMotion &&
            !JarvisV3Home._introPlayedThisLaunch);
    JarvisV3Home._introPlayedThisLaunch = true;
    if (!_settings.loaded) _settings.load();
    conversation.load();
    _modes.ensureLoaded();
    autoHide.setActivity(activity.value);
    autoHide.reveal();
  }

  void _onActivity() => autoHide.setActivity(activity.value);

  int _seen = 0;
  void _onConversation() {
    if (conversation.hasPendingNotice) {
      autoHide.hold(ChatHold.pendingNotice);
    } else {
      autoHide.release(ChatHold.pendingNotice);
    }
    final n = conversation.entries.length;
    if (n != _seen || conversation.liveTranscript.isNotEmpty) {
      _seen = n;
      autoHide.reveal();
    }
  }

  void _onSettings() => autoHide.configure(
    enabled: _settings.autoHide,
    delay: _settings.delay,
    showWhileSpeaking: _settings.showWhileSpeaking,
  );

  void _onFocus() => _focus.hasFocus
      ? autoHide.hold(ChatHold.inputFocus)
      : autoHide.release(ChatHold.inputFocus);

  @override
  void didChangeMetrics() {
    // The keyboard is visible while the bottom view inset is non-zero.
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final open = views.first.viewInsets.bottom > 0;
    open
        ? autoHide.hold(ChatHold.keyboard)
        : autoHide.release(ChatHold.keyboard);
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    autoHide.reveal();
    widget.bindings.onCommand(text);
  }

  Future<void> openHistory() async {
    autoHide.hold(ChatHold.historyOpen);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ConversationHistoryScreen(store: conversation, settings: _settings),
      ),
    );
    if (mounted) autoHide.release(ChatHold.historyOpen);
  }

  void skipIntro() {
    for (final k in [_stageKey]) {
      k.currentState?.skipIntro();
    }
    if (mounted) setState(() => _introRunning = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    activity.removeListener(_onActivity);
    conversation.removeListener(_onConversation);
    _settings.removeListener(_onSettings);
    _focus.removeListener(_onFocus);
    activity.dispose();
    conversation.dispose();
    autoHide.dispose();
    _aira.dispose();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      _settings.reduceMotion ||
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  Widget _visual(JarvisVisualMode mode) => ValueListenableBuilder<String>(
    valueListenable: HologramThemeStore.instance,
    builder: (context, theme, _) => HolographicStage(
      key: _stageKey,
      activity: activity,
      theme: theme,
      soundLevel: widget.bindings.soundLevel,
      onTap: () {
        widget.bindings.toggleMic();
      },
      playIntro: _introRunning && !_reduceMotion,
      reduceMotion: _reduceMotion,
      onIntroFinished: () {
        if (mounted && _introRunning) setState(() => _introRunning = false);
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final b = widget.bindings;
    return Material(
      color: NeonColors.background,
      child: ValueListenableBuilder<JarvisVisualMode>(
        valueListenable: _modes,
        builder: (context, mode, _) => Stack(
          fit: StackFit.expand,
          children: [
            // Centre: the selected assistant model, fullscreen.
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: _reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 450),
                child: KeyedSubtree(
                  key: const ValueKey('v3-real-3d'),
                  child: _visual(mode),
                ),
              ),
            ),
            // Soft vignette so the header and dock read cleanly over the scene.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xCC000000),
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0xE6000000),
                    ],
                    stops: [0, 0.16, 0.6, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Column(
                children: [
                  SafeArea(bottom: false, child: _header()),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        conversation,
                        autoHide,
                        _settings,
                      ]),
                      builder: (context, _) => Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          widthFactor: 1,
                          heightFactor: 0.32,
                          child: Column(
                            children: [
                              if (conversation.hasPendingNotice)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    key: const ValueKey('v3-ack-notice'),
                                    onPressed: () {
                                      conversation.acknowledgeAll();
                                      activity.acknowledgeError();
                                    },
                                    child: const Text(
                                      'Dismiss',
                                      style: TextStyle(color: NeonColors.gold),
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: NeonConversationPanel(
                                  entries: conversation.entries,
                                  liveTranscript: conversation.liveTranscript,
                                  visible: autoHide.visible,
                                  settings: _settings,
                                  scrollController: _scroll,
                                  reduceMotion: _reduceMotion,
                                  onScrollActive: (on) => on
                                      ? autoHide.hold(ChatHold.scrolling)
                                      : autoHide.release(ChatHold.scrolling),
                                  onTap: autoHide.reveal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: ValueListenableBuilder<AssistantActivity>(
                      valueListenable: activity,
                      builder: (context, a, _) => NeonInputDock(
                        controller: _input,
                        focusNode: _focus,
                        activity: a,
                        micActive: a == AssistantActivity.listening,
                        glow: _settings.glow,
                        onSend: _send,
                        onMicrophone: () {
                          autoHide.reveal();
                          b.toggleMic();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_introRunning)
              Positioned(
                right: 8,
                top: 60 + MediaQuery.paddingOf(context).top,
                child: TextButton(
                  key: const ValueKey('v3-skip-intro'),
                  onPressed: skipIntro,
                  child: const Text(
                    'Skip intro',
                    style: TextStyle(color: NeonColors.gold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final b = widget.bindings;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('v3-menu'),
            tooltip: 'Menu',
            icon: const Icon(Icons.menu_rounded, color: NeonColors.gold),
            onPressed: widget.onOpenMenu,
          ),
          Expanded(
            child: GestureDetector(
              onLongPress: widget.onLongPressTitle,
              onTap: openHistory,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const JarvisWordmark(size: 21),
                  const SizedBox(height: 2),
                  ListenableBuilder(
                    listenable: Listenable.merge([activity, b.source]),
                    builder: (context, _) {
                      final st = headerStatus(
                        activity: activity.value,
                        aiVerified: b.aiVerified(),
                        aiErrorKind: b.aiErrorKind(),
                        standbyMic: b.standbyMic(),
                      );
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: st.color,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: st.color, blurRadius: 6),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              st.label,
                              key: const ValueKey('v3-status'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: st.color.withValues(alpha: 0.9),
                                fontSize: 10,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('v3-settings'),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, color: NeonColors.gold),
            onPressed: widget.onOpenSettings,
          ),
        ],
      ),
    );
  }
}

/// Full conversation history (opened from the title or the menu).
class ConversationHistoryScreen extends StatelessWidget {
  const ConversationHistoryScreen({
    super.key,
    required this.store,
    required this.settings,
  });
  final ConversationStore store;
  final ChatInterfaceSettings settings;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: NeonColors.background,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: NeonColors.gold,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Conversation'),
          // The same model line as Settings, Diagnostics and Control Center.
          ListenableBuilder(
            listenable: SettingsService.instance,
            builder: (c, _) => Text(
              'AI model: ${SettingsService.instance.modelLabel}',
              key: const ValueKey('chat-model'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Clear conversation',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Clear the conversation?'),
                content: const Text(
                  'This removes the saved JARVIS conversation from this device.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            );
            if (ok == true) await store.clear();
          },
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: store,
      builder: (context, _) => store.entries.isEmpty
          ? const Center(
              child: Text(
                'No conversation yet.',
                style: TextStyle(color: Colors.white60),
              ),
            )
          : ListView.builder(
              key: const ValueKey('v3-history-list'),
              padding: const EdgeInsets.all(14),
              itemCount: store.entries.length,
              itemBuilder: (c, i) {
                final e = store.entries[i];
                return NeonMessageBubble(
                  role: e.role,
                  text: e.text,
                  kind: e.kind,
                  settings: settings,
                );
              },
            ),
    ),
  );
}
