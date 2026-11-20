import 'package:flutter/material.dart';

/// One continuous input surface; explicit decoration overrides the app theme.
class NeonComposer extends StatelessWidget {
  const NeonComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onMicrophone,
    this.listening = false,
    this.enabled = true,
    this.inputKey,
    this.micKey,
    this.sendKey,
    this.extra,
    this.hint = 'Ask JARVIS privately',
  });
  final TextEditingController controller;
  final VoidCallback onSend, onMicrophone;
  final bool listening, enabled;
  final Key? inputKey, micKey, sendKey;
  final Widget? extra;
  final String hint;

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00E5FF), gold = Color(0xFFFFC86B);
    return Container(
      key: const ValueKey('unified-composer'),
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(colors: [cyan, gold]),
        boxShadow: [
          BoxShadow(
            color: cyan.withValues(alpha: .22),
            blurRadius: 14,
            offset: const Offset(-3, 0),
          ),
          BoxShadow(
            color: gold.withValues(alpha: .18),
            blurRadius: 14,
            offset: const Offset(3, 0),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.only(left: 16, right: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF071116),
          borderRadius: BorderRadius.circular(29),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: inputKey,
                controller: controller,
                enabled: enabled,
                onSubmitted: (_) {
                  if (enabled) onSend();
                },
                textInputAction: TextInputAction.send,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: hint,
                  hintStyle: const TextStyle(color: Colors.white60),
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            IconButton(
              key: micKey,
              tooltip: listening ? 'Stop listening' : 'Speak to JARVIS',
              onPressed: enabled ? onMicrophone : null,
              icon: Icon(listening ? Icons.mic : Icons.mic_none, color: cyan),
            ),
            if (extra != null) extra!,
            IconButton(
              key: sendKey,
              tooltip: 'Send to native JARVIS',
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.send_rounded, color: gold),
            ),
          ],
        ),
      ),
    );
  }
}
