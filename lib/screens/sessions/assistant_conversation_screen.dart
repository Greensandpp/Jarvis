import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../brain/jarvis_brain_service.dart';
import '../../services/conversational_memory_service.dart';
import '../../services/jarvis_service.dart';

/// Shared conversation and approvals live behind Menu, keeping the main avatar
/// screen uncluttered. No second AI session or separate memory store.
class AssistantConversationScreen extends StatefulWidget {
  const AssistantConversationScreen({super.key});
  @override
  State<AssistantConversationScreen> createState() =>
      _AssistantConversationScreenState();
}

class _AssistantConversationScreenState
    extends State<AssistantConversationScreen> {
  final memory = ConversationalMemoryService.instance;
  final jarvis = JarvisService.instance;
  final input = TextEditingController();
  @override
  void initState() {
    super.initState();
    memory.init();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void submit([String? text]) {
    final command = (text ?? input.text).trim();
    if (command.isEmpty) return;
    input.clear();
    jarvis.processCommand(command);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Conversation')),
    body: ListenableBuilder(
      listenable: Listenable.merge([memory, jarvis]),
      builder: (context, _) {
        final busy =
            jarvis.phase == JarvisPhase.thinking ||
            jarvis.phase == JarvisPhase.executing;
        final messages = memory.persistedHistory;
        return Column(
          children: [
            Expanded(
              child: ListView(
                reverse: true,
                padding: const EdgeInsets.all(16),
                children: [
                  for (final h in messages.reversed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            h['role'] == 'user' ? 'You' : 'JARVIS',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          MarkdownBody(
                            data: h['content'] ?? '',
                            selectable: true,
                            onTapLink: (text, href, title) {
                              final u = Uri.tryParse(href ?? '');
                              if (u != null &&
                                  u.scheme == 'https' &&
                                  u.host.isNotEmpty &&
                                  u.userInfo.isEmpty) {
                                launchUrl(
                                  u,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  if (messages.isEmpty)
                    const Text('Your conversation will appear here.'),
                ],
              ),
            ),
            if (JarvisBrainService.instance.hasPending)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        JarvisBrainService.instance.brain.pending!.description,
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => submit('no'),
                      child: const Text('No'),
                    ),
                    FilledButton(
                      onPressed: busy ? null : () => submit('yes'),
                      child: const Text('Approve'),
                    ),
                  ],
                ),
              ),
            SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      onSubmitted: busy ? null : (_) => submit(),
                      decoration: const InputDecoration(
                        hintText: 'Message JARVIS',
                        contentPadding: EdgeInsets.all(12),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: busy ? 'Cancel request' : 'Send',
                    onPressed: busy
                        ? () => jarvis.processCommand('cancel')
                        : submit,
                    icon: Icon(busy ? Icons.stop : Icons.send),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
