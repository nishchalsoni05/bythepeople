import 'package:by_the_people/domain/entities/donation.dart';

class FoundationStats {
  final int claimed, distributed, beneficiaries;
  const FoundationStats(this.claimed, this.distributed, this.beneficiaries);
  factory FoundationStats.fromJson(Map<String, dynamic>? j) => FoundationStats(
        ((j?['claimed'] ?? 0) as num).toInt(),
        ((j?['distributed'] ?? 0) as num).toInt(),
        ((j?['beneficiaries'] ?? 0) as num).toInt(),
      );
}

class Foundation {
  final int id, hue, activeClaims;
  final String name, about, address;
  final String? regNo;
  final bool verified;
  final List<String> needs;
  final FoundationStats stats;
  const Foundation({
    required this.id, required this.name, required this.about, required this.needs, required this.address,
    required this.verified, this.regNo, required this.hue, required this.stats, this.activeClaims = 0,
  });

  factory Foundation.fromJson(Map<String, dynamic> j) => Foundation(
        id: j['id'] as int,
        name: (j['name'] ?? j['orgName'] ?? '').toString(),
        about: (j['about'] ?? '').toString(),
        needs: ((j['needs'] ?? const []) as List).map((e) => '$e').toList(),
        address: (j['address'] ?? '').toString(),
        verified: j['verified'] == true,
        regNo: j['regNo'] as String?,
        hue: ((j['hue'] ?? 160) as num).toInt(),
        stats: FoundationStats.fromJson(j['stats'] is Map ? Map<String, dynamic>.from(j['stats']) : null),
        activeClaims: ((j['activeClaims'] ?? 0) as num).toInt(),
      );
}

class FoundationDashboard {
  final FoundationStats stats;
  final List<Donation> activeClaims, nearbyAvailable;
  final List<String> needs;
  const FoundationDashboard(this.stats, this.activeClaims, this.nearbyAvailable, this.needs);

  factory FoundationDashboard.fromJson(Map<String, dynamic> j) => FoundationDashboard(
        FoundationStats.fromJson(j['stats'] is Map ? Map<String, dynamic>.from(j['stats']) : null),
        ((j['activeClaims'] ?? const []) as List).map((e) => Donation.fromJson(Map<String, dynamic>.from(e))).toList(),
        ((j['nearbyAvailable'] ?? const []) as List).map((e) => Donation.fromJson(Map<String, dynamic>.from(e))).toList(),
        ((j['needs'] ?? const []) as List).map((e) => '$e').toList(),
      );
}
