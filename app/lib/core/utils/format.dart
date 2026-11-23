const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

DateTime dt(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

String fmtDate(int ms) {
  final d = dt(ms);
  return '${d.day} ${_months[d.month - 1]}';
}

String fmtDateLong(int ms) {
  final d = dt(ms);
  return '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
}

String fmtTime(int ms) {
  final d = dt(ms);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String relative(int ms) {
  final diff = DateTime.now().difference(dt(ms));
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return fmtDate(ms);
}

String whenLabel(int ms) {
  final now = DateTime.now();
  final d = dt(ms);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today, ${fmtTime(ms)}';
  if (diff == 1) return 'Tomorrow, ${fmtTime(ms)}';
  if (diff == -1) return 'Yesterday';
  return fmtDateLong(ms);
}

/// Distance label. Empty when unknown or 50 km or more (far-away noise is never shown).
String km(double? v) {
  if (v == null || v >= 20) return '';
  if (v < 1) return '${(v * 1000).round()} m';
  return '${v.toStringAsFixed(1)} km';
}

String statusLabel(String s) => const {
      'open': 'Open issue',
      'event': 'Needs volunteers',
      'in_progress': 'In progress',
      'pending_verification': 'Awaiting verification',
      'closed': 'Resolved',
    }[s] ?? s;

/// "Raipur, Chhattisgarh" style place line for an issue; never shows coverage jargon.
String placeLine(String? city, String? state, {String? address}) {
  final parts = [city, state].whereType<String>().where((e) => e.trim().isNotEmpty).toList();
  if (parts.isNotEmpty) return parts.join(', ');
  return (address ?? '').trim();
}
