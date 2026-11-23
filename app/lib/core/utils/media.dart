import 'package:by_the_people/core/config/env.dart';

/// Server media paths are relative (`/uploads/ab12.jpg`); prefix them with the API base URL.
String mediaUrl(String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return '${Env.apiBaseUrl}${path.startsWith('/') ? '' : '/'}$path';
}

bool isVideoPath(String path) {
  final p = path.toLowerCase().split('?').first;
  return p.endsWith('.mp4') || p.endsWith('.mov') || p.endsWith('.m4v') || p.endsWith('.webm');
}

String mimeForPath(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.webp')) return 'image/webp';
  if (p.endsWith('.mp4')) return 'video/mp4';
  if (p.endsWith('.mov')) return 'video/quicktime';
  return 'image/jpeg';
}
