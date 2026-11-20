/// Select from engine-reported voices only. Gender is never inferred from a
/// pitch change or an opaque Android voice ID. Local fallback must be offline.
Map<String, String>? selectOfflineVoice(
  List<dynamic> voices,
  String languageTag, {
  bool female = true,
}) {
  final target = languageTag.toLowerCase().replaceAll('_', '-');
  final candidates = voices.whereType<Map>().where((v) {
    final locale = '${v['locale'] ?? ''}'.toLowerCase().replaceAll('_', '-');
    final network = '${v['network_required'] ?? v['networkRequired'] ?? ''}'
        .toLowerCase();
    return '${v['name'] ?? ''}'.isNotEmpty &&
        locale.split('-').first == target.split('-').first &&
        (network == 'false' || network == '0') &&
        !'${v['features'] ?? ''}'.toLowerCase().contains('notinstalled');
  }).toList();
  int score(Map v) {
    final name = '${v['name']}'.toLowerCase();
    final gender = '${v['gender'] ?? ''}'.toLowerCase();
    final isFemale =
        gender == 'female' ||
        (name.contains('female') && !name.contains('not female'));
    return (female && isFemale ? 10000 : 0) +
        ('${v['locale']}'.toLowerCase().replaceAll('_', '-') == target
            ? 1000
            : 0) +
        (name.contains('neural') ? 500 : 0) +
        (int.tryParse('${v['quality'] ?? 0}') ??
            const {
              'very high': 500,
              'high': 400,
              'normal': 300,
              'low': 200,
              'very low': 100,
            }['${v['quality']}'.toLowerCase()] ??
            0);
  }

  candidates.sort((a, b) => score(b).compareTo(score(a)));
  if (candidates.isEmpty) return null;
  final selected = candidates.first;
  return {'name': '${selected['name']}', 'locale': '${selected['locale']}'};
}
