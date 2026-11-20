import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../brain/memory_backup.dart';
import '../../services/conversational_memory_service.dart';

/// Small dialogs added to the original memory sheet: correct a fact (history
/// kept, undo available) and passphrase-encrypted export/import.
Future<String?> _ask(BuildContext context, String title, {String initial = '', bool secret = false, int lines = 1}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, obscureText: secret, maxLines: secret ? 1 : lines, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
      ],
    ),
  );
}

void _toast(BuildContext context, String msg) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));

Future<void> correctFactDialog(BuildContext context, MemoryFact f) async {
  final m = ConversationalMemoryService.instance;
  final v = await _ask(context, 'Correct this memory', initial: f.fact, lines: 3);
  if (v == null || v.trim().isEmpty) return;
  await m.correctFact(f.id, v);
  if (context.mounted) _toast(context, 'Memory corrected. The previous version is kept (undo available).');
}

Future<void> undoCorrection(BuildContext context, MemoryFact f) async {
  await ConversationalMemoryService.instance.undoCorrection(f.id);
  if (context.mounted) _toast(context, 'Correction undone.');
}

Future<void> exportMemoryDialog(BuildContext context) async {
  final pass = await _ask(context, 'Backup passphrase (min 6 characters)', secret: true);
  if (pass == null || !context.mounted) return;
  try {
    final data = await ConversationalMemoryService.instance.exportEncrypted(pass);
    await Clipboard.setData(ClipboardData(text: data));
    if (context.mounted) {
      _toast(context, 'Encrypted backup copied to the clipboard. Save it somewhere safe; it needs the passphrase.');
    }
  } on BackupException catch (e) {
    if (context.mounted) _toast(context, e.message);
  }
}

Future<void> importMemoryDialog(BuildContext context) async {
  final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
  if (!context.mounted) return;
  final data = await _ask(context, 'Paste the encrypted backup', initial: clip.contains('jarvis-memory-backup') ? clip : '', lines: 4);
  if (data == null || !context.mounted) return;
  final pass = await _ask(context, 'Backup passphrase', secret: true);
  if (pass == null || !context.mounted) return;
  try {
    final n = await ConversationalMemoryService.instance.importEncrypted(data, pass);
    if (context.mounted) _toast(context, 'Imported $n new memories (duplicates skipped).');
  } on BackupException catch (e) {
    if (context.mounted) _toast(context, e.message);
  }
}
