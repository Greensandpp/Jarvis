/// Bounded, process-local handoff between supported conversation engines.
/// No disk, networking, tool execution or credentials are stored here.
class HybridConversationContext {
  static final instance = HybridConversationContext();
  final List<({String user, String assistant})> _turns = [];
  List<({String user, String assistant})> get turns => List.unmodifiable(_turns);
  String _bounded(String text) => text.length <= 2000 ? text : text.substring(0, 2000);

  void addTurn(String user, String assistant) {
    if (user.trim().isEmpty || assistant.trim().isEmpty) return;
    final turn = (user: _bounded(user.trim()), assistant: _bounded(assistant.trim()));
    if (_turns.isNotEmpty && _turns.last == turn) return;
    _turns.add(turn);
    if (_turns.length > 4) _turns.removeAt(0);
  }

  String get prompt => _turns.map((t) => 'User: ${t.user}\nAssistant: ${t.assistant}').join('\n');
  void clear() => _turns.clear();
}
