import 'package:flutter/material.dart';

import 'assistant_activity.dart';
import 'neon_theme.dart';

/// The single glowing rounded-rectangle input: text field, microphone and
/// send button all inside one dock. It lives in the scaffold body, so the
/// keyboard inset lifts it, and the caller wraps it in a bottom SafeArea.
class NeonInputDock extends StatelessWidget {
  const NeonInputDock({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.activity,
    required this.micActive,
    required this.onSend,
    required this.onMicrophone,
    this.glow = 0.6,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final AssistantActivity activity;

  /// True only when the recogniser is really capturing.
  final bool micActive;
  final VoidCallback onSend;
  final VoidCallback onMicrophone;
  final double glow;

  @override
  Widget build(BuildContext context) {
    final edge = micActive ? NeonColors.cyan : NeonColors.amber;
    return Container(
      key: const ValueKey('v3-dock'),
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      padding: const EdgeInsets.only(left: 18, right: 6),
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: const Color(0xE6080604),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: edge.withValues(alpha: 0.75 + 0.25 * glow), width: 1.4),
        boxShadow: [
          BoxShadow(color: edge.withValues(alpha: 0.45 * glow), blurRadius: 18, spreadRadius: 0.5),
          BoxShadow(color: edge.withValues(alpha: 0.18 * glow), blurRadius: 40, spreadRadius: 2),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('v3-dock-input'),
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              maxLength: 1000,
              textInputAction: TextInputAction.send,
              keyboardType: TextInputType.multiline,
              onSubmitted: (_) => onSend(),
              cursorColor: NeonColors.amber,
              style: const TextStyle(color: NeonColors.jarvisText, fontSize: 16),
              decoration: const InputDecoration(
                counterText: '',
                hintText: 'Message JARVIS…',
                hintStyle: TextStyle(color: Color(0x99FFE2A8)),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('v3-dock-mic'),
            tooltip: micActive ? 'Stop listening' : 'Speak to JARVIS',
            onPressed: onMicrophone,
            icon: Icon(micActive ? Icons.mic : Icons.mic_none_rounded,
                color: micActive ? NeonColors.cyan : NeonColors.gold),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, v, _) {
              final canSend = v.text.trim().isNotEmpty;
              return IconButton(
                key: const ValueKey('v3-dock-send'),
                tooltip: 'Send',
                // Always active: a tap straight after typing must not be
                // lost to a rebuild. An empty message is ignored by onSend.
                onPressed: onSend,
                icon: Icon(Icons.send_rounded,
                    color: canSend ? NeonColors.amber : NeonColors.amber.withValues(alpha: 0.35)),
              );
            },
          ),
        ],
      ),
    );
  }
}
