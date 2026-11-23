import 'package:by_the_people/domain/entities/comment.dart';

class DonationEvent {
  final String status;
  final String? note;
  final int createdAt;
  final PersonRef? actor;
  const DonationEvent(this.status, this.note, this.createdAt, this.actor);
  factory DonationEvent.fromJson(Map<String, dynamic> j) => DonationEvent(
        (j['status'] ?? '').toString(),
        j['note'] as String?,
        ((j['createdAt'] ?? 0) as num).toInt(),
        j['actor'] is Map ? PersonRef.fromJson(Map<String, dynamic>.from(j['actor'])) : null,
      );
}

class Distribution {
  final String note;
  final int beneficiaries;
  final List<String> media;
  const Distribution(this.note, this.beneficiaries, this.media);
}

class Claimer {
  final int id, hue;
  final String name;
  final String? orgName;
  const Claimer(this.id, this.name, this.orgName, this.hue);
  String get label => orgName ?? name;
}

class Donation {
  final int id, expiresAt, likeCount, commentCount, shareCount;
  final int? servings, preparedAt, expiresInMinutes, claimedAt, etaAt, lockExpiresAt, pickedUpAt, distributedAt;
  final String kind, kindLabel, title, description, quantity, veg, freshness, address, pickupNote, status, shareText;
  final String? publicUrl;
  final double lat, lng;
  final double? distanceKm;
  final List<String> media;
  final bool hygieneAck, canClaim, claimedByMe, likedByMe;
  final PersonRef donor;
  final Claimer? claimedBy;
  final Distribution? distribution;
  final List<DonationEvent> timeline;

  const Donation({
    required this.id, required this.kind, required this.kindLabel, required this.title, this.description = '',
    this.quantity = '', this.servings, this.veg = 'na', this.preparedAt, required this.expiresAt, this.expiresInMinutes,
    this.freshness = 'fresh', required this.lat, required this.lng, this.address = '', this.pickupNote = '',
    this.media = const [], this.hygieneAck = false, required this.donor, required this.status, this.claimedBy,
    this.claimedAt, this.etaAt, this.lockExpiresAt, this.pickedUpAt, this.distributedAt, this.distribution,
    this.distanceKm, this.canClaim = false, this.claimedByMe = false, this.likeCount = 0, this.likedByMe = false,
    this.commentCount = 0, this.shareCount = 0, this.shareText = '', this.publicUrl, this.timeline = const [],
  });

  factory Donation.fromJson(Map<String, dynamic> j) {
    int? opt(String k) => (j[k] as num?)?.toInt();
    int n(String k) => ((j[k] ?? 0) as num).toInt();
    final claimer = j['claimedBy'];
    final dist = j['distribution'];
    return Donation(
      id: j['id'] as int,
      kind: (j['kind'] ?? 'other').toString(),
      kindLabel: (j['kindLabel'] ?? 'Other').toString(),
      title: (j['title'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      quantity: (j['quantity'] ?? '').toString(),
      servings: opt('servings'),
      veg: (j['veg'] ?? 'na').toString(),
      preparedAt: opt('preparedAt'),
      expiresAt: n('expiresAt'),
      expiresInMinutes: opt('expiresInMinutes'),
      freshness: (j['freshness'] ?? 'fresh').toString(),
      lat: ((j['lat'] ?? 0) as num).toDouble(),
      lng: ((j['lng'] ?? 0) as num).toDouble(),
      address: (j['address'] ?? '').toString(),
      pickupNote: (j['pickupNote'] ?? '').toString(),
      media: ((j['media'] ?? const []) as List).map((e) => '$e').toList(),
      hygieneAck: j['hygieneAck'] == true,
      donor: PersonRef.fromJson(Map<String, dynamic>.from(j['donor'] ?? const {})),
      status: (j['status'] ?? 'available').toString(),
      claimedBy: claimer is Map
          ? Claimer(claimer['id'] as int, '${claimer['name'] ?? ''}', claimer['orgName'] as String?, ((claimer['hue'] ?? 160) as num).toInt())
          : null,
      claimedAt: opt('claimedAt'),
      etaAt: opt('etaAt'),
      lockExpiresAt: opt('lockExpiresAt'),
      pickedUpAt: opt('pickedUpAt'),
      distributedAt: opt('distributedAt'),
      distribution: dist is Map
          ? Distribution((dist['note'] ?? '').toString(), ((dist['beneficiaries'] ?? 0) as num).toInt(),
              ((dist['media'] ?? const []) as List).map((e) => '$e').toList())
          : null,
      distanceKm: (j['distanceKm'] as num?)?.toDouble(),
      canClaim: j['canClaim'] == true,
      claimedByMe: j['claimedByMe'] == true,
      likeCount: n('likeCount'),
      likedByMe: j['likedByMe'] == true,
      commentCount: n('commentCount'),
      shareCount: n('shareCount'),
      shareText: (j['shareText'] ?? '').toString(),
      publicUrl: j['publicUrl'] as String?,
      timeline: ((j['timeline'] ?? const []) as List).map((e) => DonationEvent.fromJson(Map<String, dynamic>.from(e))).toList(),
    );
  }

  bool get isFood => kind == 'food';
  bool get isAvailable => status == 'available';
  bool get isClaimed => status == 'claimed';
  bool get isPickedUp => status == 'picked_up';
  bool get isDone => status == 'distributed';
  bool get isDead => status == 'expired' || status == 'cancelled';
  bool get isActive => isAvailable || isClaimed || isPickedUp;

  bool isDonor(int? meId) => meId != null && donor.id == meId;

  /// Freshness computed from the clock, so countdowns stay right between refreshes.
  /// Food is critical under 60 minutes, "soon" under 2 hours.
  String liveFreshness([DateTime? now]) {
    final left = expiresAt - (now ?? DateTime.now()).millisecondsSinceEpoch;
    if (left <= 0) return 'expired';
    if (!isFood) return left < 24 * 3600000 ? 'soon' : 'fresh';
    if (left < 60 * 60000) return 'critical';
    if (left < 120 * 60000) return 'soon';
    return 'fresh';
  }
}

class DonationDraft {
  final String kind, title, description, quantity, address, pickupNote;
  final int? servings, preparedAt;
  final int? shelfHours;
  final String? veg;
  final double lat, lng;
  final List<String> media;
  final bool hygieneAck;
  const DonationDraft({
    required this.kind, required this.title, required this.description, required this.quantity, required this.address,
    this.pickupNote = '', this.servings, this.preparedAt, this.shelfHours, this.veg, required this.lat, required this.lng,
    this.media = const [], this.hygieneAck = false,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'title': title,
        'description': description,
        'quantity': quantity,
        if (servings != null) 'servings': servings,
        if (veg != null) 'veg': veg,
        if (preparedAt != null) 'preparedAt': preparedAt,
        if (shelfHours != null) 'shelfHours': shelfHours,
        'lat': lat,
        'lng': lng,
        'address': address,
        if (pickupNote.isNotEmpty) 'pickupNote': pickupNote,
        if (media.isNotEmpty) 'media': media,
        'hygieneAck': hygieneAck,
      };
}
