import 'package:by_the_people/domain/entities/models.dart';

/// A comment on an issue (shared shape with gatherings and donations).
class IssueComment {
  final int id, createdAt;
  final String body;
  final Person author;
  final List<String> media;
  IssueComment(this.id, this.body, this.author, this.createdAt, this.media);
  factory IssueComment.fromJson(Map<String, dynamic> j) => IssueComment(
        j['id'] ?? 0, '${j['body'] ?? ''}', Person.fromJson(Map<String, dynamic>.from(j['author'] as Map)),
        (j['createdAt'] ?? 0) as int, ((j['media'] ?? const []) as List).map((e) => '$e').toList(),
      );
}

/// Result of POST /issues/:id/share.
class ShareInfo {
  final int shareCount;
  final String shareText, publicUrl;
  ShareInfo(this.shareCount, this.shareText, this.publicUrl);
  factory ShareInfo.fromJson(Map<String, dynamic> j) =>
      ShareInfo((j['shareCount'] ?? 0) as int, '${j['shareText'] ?? ''}', '${j['publicUrl'] ?? ''}');
}

class CategoryCount {
  final String category, label;
  final int count, open;
  CategoryCount(this.category, this.label, this.count, this.open);
  factory CategoryCount.fromJson(Map<String, dynamic> j) =>
      CategoryCount('${j['category']}', '${j['label'] ?? j['category']}', (j['count'] ?? 0) as int, (j['open'] ?? 0) as int);
}

class AdminDashboard {
  final Map<String, int> counts;
  final double? avgResolutionHours;
  final List<CategoryCount> byCategory;
  final List<Issue> topIssues;
  final int pendingFoundations;
  final List<TimelineEntry> recent;
  AdminDashboard(this.counts, this.avgResolutionHours, this.byCategory, this.topIssues, this.pendingFoundations, this.recent);
  factory AdminDashboard.fromJson(Map<String, dynamic> j) => AdminDashboard(
        ((j['counts'] ?? const {}) as Map).map((k, v) => MapEntry('$k', (v as num).toInt())),
        (j['avgResolutionHours'] as num?)?.toDouble(),
        ((j['byCategory'] ?? const []) as List).map((e) => CategoryCount.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        ((j['topIssues'] ?? const []) as List).map((e) => Issue.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        ((j['pendingFoundations'] ?? 0) as num).toInt(),
        ((j['recent'] ?? const []) as List).map((e) => TimelineEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
  int count(String k) => counts[k] ?? 0;
}

/// A foundation row in the admin verification list.
class FoundationRow {
  final int id, hue;
  final String name;
  final String? about, address, regNo;
  final bool verified;
  final List<String> needs;
  final int claimed, distributed, beneficiaries;
  FoundationRow(this.id, this.hue, this.name, this.about, this.address, this.regNo, this.verified, this.needs, this.claimed,
      this.distributed, this.beneficiaries);
  factory FoundationRow.fromJson(Map<String, dynamic> j) {
    final st = (j['stats'] ?? const {}) as Map;
    int n(String k) => ((st[k] ?? 0) as num).toInt();
    return FoundationRow(
      j['id'] ?? 0, (j['hue'] ?? 200) as int, '${j['name'] ?? j['orgName'] ?? 'Foundation'}', j['about'] as String?, j['address'] as String?,
      j['regNo'] as String?, (j['verified'] ?? false) as bool, ((j['needs'] ?? const []) as List).map((e) => '$e').toList(),
      n('claimed'), n('distributed'), n('beneficiaries'),
    );
  }
  Person get asPerson => Person(id, name, hue, role: 'foundation', orgName: name, verified: verified);
}

/// Minimal gathering reference used on the neta dashboard (full model lives with the gatherings feature).
class GatheringLite {
  final int id;
  final String title, typeLabel;
  final String? address;
  final int startAt, goingCount;
  GatheringLite(this.id, this.title, this.typeLabel, this.address, this.startAt, this.goingCount);
  factory GatheringLite.fromJson(Map<String, dynamic> j) => GatheringLite(
        j['id'] ?? 0, '${j['title'] ?? ''}', '${j['typeLabel'] ?? j['type'] ?? ''}', j['address'] as String?,
        (j['startAt'] ?? 0) as int, (j['goingCount'] ?? 0) as int,
      );
}

class NetaDashboard {
  final Neta politician;
  final Map<String, int> counts;
  final double? resolutionRate;
  final List<Issue> topIssues;
  final List<GatheringLite> upcomingGatherings;
  NetaDashboard(this.politician, this.counts, this.resolutionRate, this.topIssues, this.upcomingGatherings);
  factory NetaDashboard.fromJson(Map<String, dynamic> j) => NetaDashboard(
        Neta.fromJson(Map<String, dynamic>.from(j['politician'] as Map)),
        ((j['counts'] ?? const {}) as Map).map((k, v) => MapEntry('$k', (v as num).toInt())),
        (j['resolutionRate'] as num?)?.toDouble(),
        ((j['topIssues'] ?? const []) as List).map((e) => Issue.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        ((j['upcomingGatherings'] ?? const []) as List).map((e) => GatheringLite.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
  int count(String k) => counts[k] ?? 0;
}
