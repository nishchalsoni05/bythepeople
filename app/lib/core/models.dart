class Person {
  final int id;
  final String name;
  final int hue;
  Person(this.id, this.name, this.hue);
  factory Person.fromJson(Map<String, dynamic> j) => Person(j['id'], j['name'], (j['hue'] ?? 200) as int);
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
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
  final String? note, userName;
  final int createdAt;
  TimelineEntry(this.status, this.note, this.userName, this.createdAt);
  factory TimelineEntry.fromJson(Map<String, dynamic> j) =>
      TimelineEntry(j['status'], j['note'], j['userName'], j['createdAt']);
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
        id: j['id'], hue: j['hue'], name: j['name'], party: j['party'], constituency: j['constituency'],
        level: j['level'], tagline: j['tagline'],
        city: j['city'], state: j['state'], region: j['region'],
        cityId: j['cityId'], stateId: j['stateId'], regionId: j['regionId'],
        parent: j['parent'] == null
            ? null
            : PolRef(j['parent']['id'], j['parent']['name'], j['parent']['party'] ?? '', '', j['parent']['level'], 20),
        stats: NetaStats.fromJson(j['stats']),
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
  UserProfile(this.id, this.points, this.hue, this.name, this.email, this.volunteer, this.alertRadiusKm, this.rank,
      this.stats, this.badges);
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        j['id'], j['points'], j['hue'], j['name'], j['email'], j['volunteer'],
        (j['alertRadiusKm'] as num).toDouble(), RankInfo.fromJson(j['rank']),
        (j['stats'] as Map).map((k, v) => MapEntry(k as String, v as int)),
        (j['badges'] as List).map((e) => BadgeInfo.fromJson(e)).toList(),
      );
  Person get asPerson => Person(id, name, hue);
}

class AppNotification {
  final int id, createdAt;
  final String type, title;
  final String? body;
  final int? issueId;
  final bool read;
  AppNotification(this.id, this.type, this.title, this.body, this.issueId, this.read, this.createdAt);
  factory AppNotification.fromJson(Map<String, dynamic> j) =>
      AppNotification(j['id'], j['type'], j['title'], j['body'], j['issueId'], j['read'], j['createdAt']);
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
