class Person {
  final int id;
  final String name;
  final int hue;
  final String role; // citizen | admin | neta | foundation
  final String? orgName;
  final bool verified;
  Person(this.id, this.name, this.hue, {this.role = 'citizen', this.orgName, this.verified = true});
  factory Person.fromJson(Map<String, dynamic> j) => Person(j['id'] ?? 0, j['name'] ?? '?', (j['hue'] ?? 200) as int,
      role: (j['role'] ?? 'citizen') as String, orgName: j['orgName'], verified: (j['verified'] ?? true) as bool);
  String get shownName => role == 'foundation' && (orgName ?? '').isNotEmpty ? orgName! : name;
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }
}

class PolRef {
  final int id;
  final String name, party, constituency, level;
  final int hue;
  PolRef(this.id, this.name, this.party, this.constituency, this.level, this.hue);
  factory PolRef.fromJson(Map<String, dynamic> j) =>
      PolRef(j['id'], j['name'], j['party'], j['constituency'], j['level'], (j['hue'] ?? 20) as int);
}

class TimelineEntry {
  final String status;
  final String? note, userName, actorRole;
  final int createdAt;
  final List<String> media;
  final String kind; // status | authority | neta | system
  TimelineEntry(this.status, this.note, this.userName, this.createdAt,
      {this.media = const [], this.actorRole, this.kind = 'status'});
  factory TimelineEntry.fromJson(Map<String, dynamic> j) => TimelineEntry(
        (j['status'] ?? 'open') as String, j['note'], (j['userName'] ?? j['actor']?['name']) as String?, (j['createdAt'] ?? 0) as int,
        media: ((j['media'] ?? const []) as List).map((e) => '$e').toList(),
        actorRole: j['actorRole'] as String?,
        kind: (j['kind'] ?? 'status') as String,
      );
}

/// The authority responsible for an issue, e.g. Raipur Municipal Corporation / Public Works / @RMC_Raipur.
class Authority {
  final String name, department, handle;
  Authority(this.name, this.department, this.handle);
  factory Authority.fromJson(Map<String, dynamic> j) =>
      Authority('${j['name'] ?? ''}', '${j['department'] ?? ''}', '${j['handle'] ?? ''}');
}

class Verification {
  final int needed, approvals, rejections, round;
  Verification(this.needed, this.approvals, this.rejections, this.round);
  factory Verification.fromJson(Map<String, dynamic> j) =>
      Verification(j['needed'], j['approvals'], j['rejections'], j['round']);
}

class AreaNames {
  final String? ward, city, state, region;
  final int? cityId, stateId, regionId;
  AreaNames({this.ward, this.city, this.state, this.region, this.cityId, this.stateId, this.regionId});
  factory AreaNames.fromJson(Map<String, dynamic> j) => AreaNames(
        ward: j['ward']?['name'], city: j['city']?['name'], state: j['state']?['name'], region: j['region']?['name'],
        cityId: j['city']?['id'], stateId: j['state']?['id'], regionId: j['region']?['id'],
      );
  String get line => [city, state].whereType<String>().join(', ');
}

/// A node of the geography tree (region > state > city).
class Area {
  final int id;
  final String name;
  final String kind; // region | state | city
  final int? parentId;
  Area(this.id, this.name, this.kind, this.parentId);
}

class ScopeSummary {
  final String scope, areaName;
  final int reported, resolved, open, events;
  final double? rate, avgDays;
  ScopeSummary(this.scope, this.areaName, this.reported, this.resolved, this.open, this.events, this.rate, this.avgDays);
  factory ScopeSummary.fromJson(Map<String, dynamic> j) => ScopeSummary(
        j['scope'], j['area']['name'], j['reported'], j['resolved'], j['open'], j['events'],
        (j['rate'] as num?)?.toDouble(), (j['avgDaysToResolve'] as num?)?.toDouble(),
      );
}

class Issue {
  final int id;
  final String title, description, category, categoryLabel, status, phase, severity;
  final String? address, resolutionNote;
  final double radiusKm, lat, lng, severityScore;
  final double? distanceKm;
  final bool? inRange;
  final int supportCount, linkedCount, volunteerCount, threshold, createdAt;
  final int? eventAt, scheduledAt, resolvedAt, closedAt;
  final Person reporter;
  final PolRef? politician;
  final List<Person> supporters, volunteers;
  final bool supportedByMe, volunteeringByMe, reportedByMe, verifiedByMe, isOrganiser;
  final List<TimelineEntry> timeline;
  final Verification? verification;
  final AreaNames area;
  // Social + authority layer (api-v3).
  final int likeCount, commentCount, shareCount, engagement;
  final bool likedByMe, escalated;
  final List<String> media;
  final Authority? authority;
  final String authorityStatus; // open | acknowledged | in_progress | resolved
  final String? assignedTo, escalationNote, shareText, publicUrl;
  final Person? escalatedBy;

  Issue({
    required this.id, required this.title, required this.description, required this.category,
    required this.categoryLabel, required this.status, required this.phase, required this.severity,
    this.address, this.resolutionNote, required this.radiusKm, required this.lat, required this.lng,
    required this.severityScore, this.distanceKm, this.inRange, required this.supportCount,
    required this.linkedCount, required this.volunteerCount, required this.threshold,
    required this.createdAt, this.eventAt, this.scheduledAt, this.resolvedAt, this.closedAt,
    required this.reporter, this.politician, required this.supporters, required this.volunteers,
    required this.supportedByMe, required this.volunteeringByMe, required this.reportedByMe,
    required this.verifiedByMe, required this.isOrganiser, required this.timeline, this.verification,
    required this.area,
    this.likeCount = 0, this.commentCount = 0, this.shareCount = 0, this.engagement = 0,
    this.likedByMe = false, this.escalated = false, this.media = const [], this.authority,
    this.authorityStatus = 'open', this.assignedTo, this.escalationNote, this.shareText, this.publicUrl,
    this.escalatedBy,
  });

  factory Issue.fromJson(Map<String, dynamic> j) {
    List<Person> people(String k) => ((j[k] ?? []) as List).map((e) => Person.fromJson(e)).toList();
    return Issue(
      id: j['id'], title: j['title'], description: j['description'] ?? '', category: j['category'],
      categoryLabel: j['categoryLabel'], status: j['status'], phase: j['phase'], severity: j['severity'],
      address: j['address'], resolutionNote: j['resolutionNote'],
      radiusKm: (j['radiusKm'] as num).toDouble(), lat: (j['lat'] as num).toDouble(), lng: (j['lng'] as num).toDouble(),
      severityScore: (j['severityScore'] as num).toDouble(),
      distanceKm: (j['distanceKm'] as num?)?.toDouble(), inRange: j['inRange'],
      supportCount: j['supportCount'], linkedCount: j['linkedCount'], volunteerCount: j['volunteerCount'],
      threshold: j['threshold'], createdAt: j['createdAt'], eventAt: j['eventAt'], scheduledAt: j['scheduledAt'],
      resolvedAt: j['resolvedAt'], closedAt: j['closedAt'],
      reporter: Person.fromJson(j['reporter']),
      politician: j['politician'] == null ? null : PolRef.fromJson(j['politician']),
      supporters: people('supporters'), volunteers: people('volunteers'),
      supportedByMe: j['supportedByMe'] ?? false, volunteeringByMe: j['volunteeringByMe'] ?? false,
      reportedByMe: j['reportedByMe'] ?? false, verifiedByMe: j['verifiedByMe'] ?? false,
      isOrganiser: j['isOrganiser'] ?? false,
      timeline: ((j['timeline'] ?? []) as List).map((e) => TimelineEntry.fromJson(e)).toList(),
      verification: j['verification'] == null ? null : Verification.fromJson(j['verification']),
      area: AreaNames.fromJson(Map<String, dynamic>.from((j['area'] ?? const <String, dynamic>{}) as Map)),
      likeCount: (j['likeCount'] ?? 0) as int, commentCount: (j['commentCount'] ?? 0) as int,
      shareCount: (j['shareCount'] ?? 0) as int, engagement: (j['engagement'] ?? 0) as int,
      likedByMe: (j['likedByMe'] ?? false) as bool, escalated: (j['escalated'] == true || j['escalated'] == 1),
      media: ((j['media'] ?? const []) as List).map((e) => '$e').toList(),
      authority: j['authority'] == null ? null : Authority.fromJson(Map<String, dynamic>.from(j['authority'] as Map)),
      authorityStatus: (j['authorityStatus'] ?? 'open') as String,
      assignedTo: j['assignedTo'] as String?, escalationNote: j['escalationNote'] as String?,
      shareText: j['shareText'] as String?, publicUrl: j['publicUrl'] as String?,
      escalatedBy: j['escalatedBy'] == null ? null : Person.fromJson(Map<String, dynamic>.from(j['escalatedBy'] as Map)),
    );
  }

  bool get isEvent => phase == 'event';
  bool get isClosed => status == 'closed';
}

class NetaStats {
  final int reported, resolved, open, criticalOpen, minSample;
  final double? rate, avgDays;
  final double simpleRate;
  final bool sampleOk;
  final String rarity;
  NetaStats(this.reported, this.resolved, this.open, this.criticalOpen, this.minSample, this.rate, this.avgDays,
      this.simpleRate, this.sampleOk, this.rarity);
  factory NetaStats.fromJson(Map<String, dynamic> j) => NetaStats(
        j['reported'], j['resolved'], j['open'], j['criticalOpen'], j['minSample'],
        (j['rate'] as num?)?.toDouble(), (j['avgDaysToResolve'] as num?)?.toDouble(),
        (j['simpleRate'] as num).toDouble(), j['sampleOk'], j['rarity'],
      );
}

class Neta {
  final int id, hue;
  final String name, party, constituency, level;
  final String? tagline, city, state, region;
  final int? cityId, stateId, regionId;
  final PolRef? parent;
  final NetaStats stats;
  final List<Neta> children;
  Neta({required this.id, required this.hue, required this.name, required this.party, required this.constituency,
      required this.level, this.tagline, this.city, this.state, this.region, this.cityId, this.stateId, this.regionId,
      this.parent, required this.stats, this.children = const []});
  factory Neta.fromJson(Map<String, dynamic> j) => Neta(
        id: j['id'], hue: (j['hue'] ?? 20) as int, name: j['name'], party: j['party'] ?? '', constituency: j['constituency'] ?? '',
        level: j['level'] ?? 'ward', tagline: j['tagline'],
        city: j['city'], state: j['state'], region: j['region'],
        cityId: j['cityId'], stateId: j['stateId'], regionId: j['regionId'],
        parent: j['parent'] == null
            ? null
            : PolRef(j['parent']['id'], j['parent']['name'], j['parent']['party'] ?? '', '', j['parent']['level'], 20),
        stats: j['stats'] == null ? NetaStats(0, 0, 0, 0, 5, null, null, 0, false, 'unrated') : NetaStats.fromJson(Map<String, dynamic>.from(j['stats'] as Map)),
        children: ((j['children'] ?? []) as List).map((e) => Neta.fromJson(e)).toList(),
      );
  String get levelLabel => const {
        'ward': 'Ward Councillor', 'mla': 'MLA', 'mp': 'Member of Parliament', 'minister': 'Minister',
      }[level] ?? level;

  /// Where this leader's authority sits, e.g. "Bengaluru" or "Karnataka" for a state minister.
  String get jurisdiction => level == 'minister' ? (state ?? '') : (city ?? state ?? '');

  /// Wider line: "Bengaluru · Karnataka" (ministers: "Karnataka · South India").
  String get jurisdictionLong => level == 'minister'
      ? [state, region].whereType<String>().join(' · ')
      : [city, state].whereType<String>().join(' · ');
}

class BadgeInfo {
  final String key, name, desc, icon;
  final bool earned;
  BadgeInfo(this.key, this.name, this.desc, this.icon, this.earned);
  factory BadgeInfo.fromJson(Map<String, dynamic> j) =>
      BadgeInfo(j['key'], j['name'], j['desc'], j['icon'], j['earned'] ?? false);
}

class RankInfo {
  final String name;
  final String? next;
  final int index, min;
  final int? nextAt;
  final double progress;
  RankInfo(this.name, this.next, this.index, this.min, this.nextAt, this.progress);
  factory RankInfo.fromJson(Map<String, dynamic> j) =>
      RankInfo(j['name'], j['next'], j['index'], j['min'], j['nextAt'], (j['progress'] as num).toDouble());
}

class UserProfile {
  final int id, points, hue;
  final String name, email;
  final bool volunteer;
  final double alertRadiusKm;
  final RankInfo rank;
  final Map<String, int> stats;
  final List<BadgeInfo> badges;
  // Role-aware fields (api-v3).
  final String role; // citizen | admin | neta | foundation
  final bool verified;
  final String? orgName, regNo, about, address, departmentName, designation;
  final List<String> needs;
  final int? politicianId;
  UserProfile(this.id, this.points, this.hue, this.name, this.email, this.volunteer, this.alertRadiusKm, this.rank,
      this.stats, this.badges,
      {this.role = 'citizen', this.verified = true, this.orgName, this.regNo, this.about, this.address,
      this.departmentName, this.designation, this.needs = const [], this.politicianId});
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        j['id'], (j['points'] ?? 0) as int, (j['hue'] ?? 200) as int, j['name'], j['email'], (j['volunteer'] ?? false) as bool,
        ((j['alertRadiusKm'] ?? 5) as num).toDouble(),
        RankInfo.fromJson(j['rank'] ?? const {'name': 'Rookie', 'index': 0, 'min': 0, 'progress': 0}),
        ((j['stats'] ?? const {}) as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())),
        ((j['badges'] ?? const []) as List).map((e) => BadgeInfo.fromJson(e)).toList(),
        role: (j['role'] ?? 'citizen') as String,
        verified: (j['verified'] ?? true) as bool,
        orgName: j['orgName'], regNo: j['regNo'], about: j['about'], address: j['address'],
        departmentName: j['departmentName'], designation: j['designation'],
        needs: ((j['needs'] ?? const []) as List).map((e) => '$e').toList(),
        politicianId: j['politicianId'] as int?,
      );
  Person get asPerson => Person(id, name, hue);

  bool get isCitizen => role == 'citizen';
  bool get isAdmin => role == 'admin';
  bool get isNeta => role == 'neta';
  bool get isFoundation => role == 'foundation';
  bool get isVerifiedFoundation => isFoundation && verified;

  /// Name to show for the account: organisation for foundations.
  String get displayName => isFoundation && (orgName ?? '').isNotEmpty ? orgName! : name;

  String get roleLabel => const {
        'citizen': 'Citizen', 'admin': 'Authority officer', 'neta': 'Neta', 'foundation': 'Foundation',
      }[role] ?? role;
}

class AppNotification {
  final int id, createdAt;
  final String type, title;
  final String? body;
  final int? issueId;
  final bool read;
  /// Deep-link target: 'issue' | 'gathering' | 'donation' plus its id.
  final String? refType;
  final int? refId;
  AppNotification(this.id, this.type, this.title, this.body, this.issueId, this.read, this.createdAt,
      {this.refType, this.refId});
  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final issueId = j['issueId'] as int?;
    final refType = (j['refType'] as String?) ?? (issueId != null ? 'issue' : null);
    final refId = (j['refId'] as int?) ?? issueId;
    return AppNotification(j['id'], j['type'], j['title'] ?? '', j['body'], issueId, (j['read'] ?? false) as bool, j['createdAt'],
        refType: refType, refId: refId);
  }
}

class Rewards {
  final int points, total;
  final List<String> reasons;
  final List<BadgeInfo> badges;
  final String? rankUpTo;
  Rewards(this.points, this.total, this.reasons, this.badges, this.rankUpTo);
  factory Rewards.fromJson(Map<String, dynamic> j) => Rewards(
        j['points'], j['total'], (j['reasons'] as List).cast<String>(),
        (j['badges'] as List).map((e) => BadgeInfo.fromJson({...e, 'earned': true})).toList(),
        j['rankUp']?['to'],
      );
}

class CategoryInfo {
  final String key, label, icon;
  final double radiusKm;
  CategoryInfo(this.key, this.label, this.icon, this.radiusKm);
  factory CategoryInfo.fromJson(Map<String, dynamic> j) =>
      CategoryInfo(j['key'], j['label'], j['icon'], (j['radiusKm'] as num).toDouble());
}

class ActionResult {
  final Issue? issue;
  final Rewards? rewards;
  final bool converted, linked;
  final String? outcome;
  ActionResult({this.issue, this.rewards, this.converted = false, this.linked = false, this.outcome});
  factory ActionResult.fromJson(Map<String, dynamic> j) => ActionResult(
        issue: j['issue'] == null ? null : Issue.fromJson(j['issue']),
        rewards: j['rewards'] == null ? null : Rewards.fromJson(j['rewards']),
        converted: j['converted'] ?? false,
        linked: j['linked'] ?? false,
        outcome: j['outcome'],
      );
}

class NetaDetail {
  final Neta neta;
  final List<Neta> children;
  final List<Issue> open, resolved;
  NetaDetail(this.neta, this.children, this.open, this.resolved);
}

class NetaList {
  final List<Neta> items;
  final List<String> parties;
  NetaList(this.items, this.parties);
}
