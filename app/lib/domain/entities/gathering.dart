import 'package:by_the_people/domain/entities/club.dart';
import 'package:by_the_people/domain/entities/comment.dart';

/// Gathering statuses: proposed, upcoming, ongoing, completed, cancelled.
class GatheringImpact {
  final int checkedIn;
  final String note;
  const GatheringImpact(this.checkedIn, this.note);
}

class Attendee {
  final int id, hue;
  final String name;
  const Attendee(this.id, this.name, this.hue);
  PersonRef get asRef => PersonRef(id, name, hue);
}

class Gathering {
  final int id, startAt, goingCount, voteCount, votesNeeded, likeCount, commentCount, shareCount;
  final int? endAt, capacity, spotsLeft;
  final String title, description, type, typeLabel, address, status, shareText;
  final String? publicUrl;
  final double lat, lng;
  final double? distanceKm;
  final PersonRef organizer;
  final ClubRef? club;
  final List<String> media;
  final bool goingByMe, checkedInByMe, votedByMe, likedByMe;
  final List<Attendee> attendees;
  final GatheringImpact? impact;

  const Gathering({
    required this.id, required this.title, required this.description, required this.type, required this.typeLabel,
    required this.lat, required this.lng, required this.address, required this.startAt, this.endAt, required this.status,
    required this.organizer, this.club, this.capacity, this.media = const [], this.goingCount = 0, this.spotsLeft,
    this.goingByMe = false, this.checkedInByMe = false, this.voteCount = 0, this.votesNeeded = 5, this.votedByMe = false,
    this.likeCount = 0, this.likedByMe = false, this.commentCount = 0, this.shareCount = 0, this.shareText = '',
    this.publicUrl, this.distanceKm, this.attendees = const [], this.impact,
  });

  factory Gathering.fromJson(Map<String, dynamic> j) {
    int n(String k, [int d = 0]) => ((j[k] ?? d) as num).toInt();
    final club = j['club'];
    final impact = j['impact'];
    return Gathering(
      id: j['id'] as int,
      title: (j['title'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      type: (j['type'] ?? 'other').toString(),
      typeLabel: (j['typeLabel'] ?? 'Gathering').toString(),
      lat: ((j['lat'] ?? 0) as num).toDouble(),
      lng: ((j['lng'] ?? 0) as num).toDouble(),
      address: (j['address'] ?? '').toString(),
      startAt: n('startAt'),
      endAt: (j['endAt'] as num?)?.toInt(),
      status: (j['status'] ?? 'upcoming').toString(),
      organizer: PersonRef.fromJson(Map<String, dynamic>.from(j['organizer'] ?? const {})),
      club: club is Map ? ClubRef(club['id'] as int, '${club['name']}') : null,
      capacity: (j['capacity'] as num?)?.toInt(),
      media: ((j['media'] ?? const []) as List).map((e) => '$e').toList(),
      goingCount: n('goingCount'),
      spotsLeft: (j['spotsLeft'] as num?)?.toInt(),
      goingByMe: j['goingByMe'] == true,
      checkedInByMe: j['checkedInByMe'] == true,
      voteCount: n('voteCount'),
      votesNeeded: n('votesNeeded', 5),
      votedByMe: j['votedByMe'] == true,
      likeCount: n('likeCount'),
      likedByMe: j['likedByMe'] == true,
      commentCount: n('commentCount'),
      shareCount: n('shareCount'),
      shareText: (j['shareText'] ?? '').toString(),
      publicUrl: j['publicUrl'] as String?,
      distanceKm: (j['distanceKm'] as num?)?.toDouble(),
      attendees: ((j['attendees'] ?? const []) as List)
          .map((e) => Attendee(e['id'] as int, '${e['name']}', ((e['hue'] ?? 200) as num).toInt()))
          .toList(),
      impact: impact is Map ? GatheringImpact(((impact['checkedIn'] ?? 0) as num).toInt(), (impact['note'] ?? '').toString()) : null,
    );
  }

  bool get isProposed => status == 'proposed';
  bool get isCancelled => status == 'cancelled';
  bool get isCompleted => status == 'completed';
  bool get isOngoing => status == 'ongoing';
  bool get isFull => capacity != null && (spotsLeft ?? 1) <= 0;
  bool get isOpen => status == 'upcoming' || status == 'ongoing';

  /// True when [meId] organised this gathering.
  bool organisedBy(int? meId) => meId != null && organizer.id == meId;

  /// Check-in window per the API: from 30 minutes before the start until the end (or start + 3h).
  bool get checkInOpenNow {
    final now = DateTime.now().millisecondsSinceEpoch;
    final from = startAt - 30 * 60000;
    final to = endAt ?? (startAt + 3 * 3600000);
    return isOpen && now >= from && now <= to;
  }
}

/// Calendar entry: `{id, title, type, startAt}`.
class GatheringLite {
  final int id, startAt;
  final String title, type;
  const GatheringLite(this.id, this.title, this.type, this.startAt);
  factory GatheringLite.fromJson(Map<String, dynamic> j) =>
      GatheringLite(j['id'] as int, (j['title'] ?? '').toString(), (j['type'] ?? 'other').toString(), ((j['startAt'] ?? 0) as num).toInt());
}

class GatheringDraft {
  final String title, description, type, address;
  final double lat, lng;
  final int startAt;
  final int? endAt, capacity, clubId;
  final List<String> media;
  final bool proposed;
  const GatheringDraft({
    required this.title, required this.description, required this.type, required this.address, required this.lat,
    required this.lng, required this.startAt, this.endAt, this.capacity, this.clubId, this.media = const [], this.proposed = false,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'type': type,
        'lat': lat,
        'lng': lng,
        'address': address,
        'startAt': startAt,
        if (endAt != null) 'endAt': endAt,
        if (capacity != null) 'capacity': capacity,
        if (clubId != null) 'clubId': clubId,
        if (media.isNotEmpty) 'media': media,
        if (proposed) 'proposed': true,
      };
}

class ClubDetail {
  final Club club;
  final List<PersonRef> members;
  final List<Gathering> upcoming;
  const ClubDetail(this.club, this.members, this.upcoming);
}
