import 'package:flutter/material.dart';

import 'chat_interface_settings.dart';
import 'conversation_store.dart';
import 'neon_theme.dart';

/// One glowing conversation card. User turns are cyan and right-aligned,
/// JARVIS turns amber and left-aligned. The glow sits on the border and
/// background, never on the glyphs, so text stays crisp.
class NeonMessageBubble extends StatelessWidget {
  const NeonMessageBubble({
    super.key,
    required this.role,
    required this.text,
    this.kind = ConversationKind.normal,
    this.live = false,
    required this.settings,
  });

  final ConversationRole role;
  final String text;
  final ConversationKind kind;
  final bool live;
  final ChatInterfaceSettings settings;

  bool get _user => role == ConversationRole.user;

  @override
  Widget build(BuildContext context) {
    final accent = kind == ConversationKind.error
        ? NeonColors.error
        : _user
            ? NeonColors.cyan
            : NeonColors.amber;
    final textColor = _user ? NeonColors.userText : NeonColors.jarvisText;
    final glow = settings.glow;
    final maxW = MediaQuery.sizeOf(context).width * 0.78;
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Color.lerp(Colors.black, accent, 0.10)!.withValues(alpha: settings.opacity),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(_user ? 18 : 4),
            bottomRight: Radius.circular(_user ? 4 : 18),
          ),
          border: Border.all(color: accent.withValues(alpha: 0.55 + 0.4 * glow), width: 1.2),
          boxShadow: [
            if (glow > 0)
              BoxShadow(color: accent.withValues(alpha: 0.35 * glow), blurRadius: 14 * glow + 2),
          ],
        ),
        child: Text(
          text,
          key: ValueKey(_user ? 'bubble-user' : 'bubble-jarvis'),
          softWrap: true,
          style: TextStyle(
            color: textColor,
            fontSize: 15 * settings.fontScale,
            height: 1.38,
            fontStyle: live ? FontStyle.italic : FontStyle.normal,
            shadows: [Shadow(color: accent.withValues(alpha: 0.35 * glow), blurRadius: 6)],
          ),
        ),
      ),
    );
    final icon = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black,
        border: Border.all(color: accent, width: 1.2),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.5 * glow), blurRadius: 8)],
      ),
      child: _user
          ? Icon(Icons.person, size: 16, color: accent, semanticLabel: 'You')
          : Center(
              child: Text('J',
                  semanticsLabel: 'JARVIS',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 14))),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: _user ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _user
            ? [Flexible(child: bubble), const SizedBox(width: 8), icon]
            : [icon, const SizedBox(width: 8), Flexible(child: bubble)],
      ),
    );
  }
}

/// The conversation layer above the dock. It fades out when the auto-hide
/// controller says so; history itself is untouched.
class NeonConversationPanel extends StatelessWidget {
  const NeonConversationPanel({
    super.key,
    required this.entries,
    required this.liveTranscript,
    required this.visible,
    required this.settings,
    required this.scrollController,
    required this.onScrollActive,
    required this.onTap,
    this.reduceMotion = false,
    this.maxRecent = 4,
  });

  final List<ConversationEntry> entries;
  final String liveTranscript;
  final bool visible;
  final ChatInterfaceSettings settings;
  final ScrollController scrollController;
  final ValueChanged<bool> onScrollActive;
  final VoidCallback onTap;
  final bool reduceMotion;

  /// The main screen shows the latest turns; the full history is one tap away.
  final int maxRecent;

  @override
  Widget build(BuildContext context) {
    final recent = entries.length > maxRecent
        ? entries.sublist(entries.length - maxRecent)
        : entries;
    final items = <Widget>[
      for (final e in recent)
        NeonMessageBubble(
            key: ObjectKey(e), role: e.role, text: e.text, kind: e.kind, settings: settings),
      if (liveTranscript.trim().isNotEmpty)
        NeonMessageBubble(
            key: const ValueKey('live-transcript'),
            role: ConversationRole.user,
            text: liveTranscript.trim(),
            live: true,
            settings: settings),
    ];
    return IgnorePointer(
      ignoring: !visible || items.isEmpty,
      child: GestureDetector(
      key: const ValueKey('v3-conversation-area'),
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: AnimatedOpacity(
        key: const ValueKey('v3-conversation-opacity'),
        opacity: visible ? 1 : 0,
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        child: IgnorePointer(
          ignoring: !visible,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification) onScrollActive(true);
              if (n is ScrollEndNotification) onScrollActive(false);
              return false;
            },
            child: ShaderMask(
              // Soft fade at the top so the bubbles melt into the scene.
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.white, Colors.white],
                stops: [0, 0.18, 1],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: ListView(
                key: const ValueKey('v3-conversation-list'),
                controller: scrollController,
                reverse: true,
                padding: const EdgeInsets.fromLTRB(14, 24, 14, 6),
                children: items.reversed.toList(),
              ),
            ),
          ),
        ),
      ),
    ));
  }
}
