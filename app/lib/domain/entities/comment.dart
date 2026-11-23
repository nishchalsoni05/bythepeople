/// A person as the welfare API describes them: `{id, name, hue, role, orgName?, verified?}`.
class PersonRef {
  final int id;
  final String name;
  final int hue;
  final String role;
  final String? orgName;
  final bool verified;
  const PersonRef(this.id, this.name, this.hue, {this.role = 'citizen', this.orgName, this.verified = false});

  factory PersonRef.fromJson(Map<String, dynamic> j) => PersonRef(
        (j['id'] ?? 0) as int,
        (j['orgName'] ?? j['name'] ?? 'Someone').toString(),
        ((j['hue'] ?? 200) as num).toInt(),
        role: (j['role'] ?? 'citizen').toString(),
        orgName: j['orgName'] as String?,
        verified: j['verified'] == true,
      );

  /// Name to show: organisations use their organisation name.
  String get label => orgName ?? name;

  String get initials {
    final parts = label.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }
}

class Comment {
  final int id, createdAt;
  final String body;
  final PersonRef author;
  final List<String> media;
  const Comment(this.id, this.body, this.author, this.createdAt, this.media);

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        (j['id'] ?? 0) as int,
        (j['body'] ?? '').toString(),
        PersonRef.fromJson(Map<String, dynamic>.from(j['author'] ?? const {})),
        ((j['createdAt'] ?? 0) as num).toInt(),
        ((j['media'] ?? const []) as List).map((e) => '$e').toList(),
      );
}

/// What the share endpoint returns: text and a public link for the system share sheet.
class ShareInfo {
  final int shareCount;
  final String shareText;
  final String? publicUrl;
  const ShareInfo(this.shareCount, this.shareText, this.publicUrl);
  factory ShareInfo.fromJson(Map<String, dynamic> j) =>
      ShareInfo(((j['shareCount'] ?? 0) as num).toInt(), (j['shareText'] ?? '').toString(), j['publicUrl'] as String?);
}

/// A mutation's updated object plus any reward earned.
class Outcome<T> {
  final T value;
  final Map<String, dynamic>? rewards;
  const Outcome(this.value, [this.rewards]);
}
