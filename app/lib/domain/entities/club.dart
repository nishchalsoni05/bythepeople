import 'package:by_the_people/domain/entities/comment.dart';

class Club {
  final int id, hue, memberCount, upcomingCount;
  final String name, description, category;
  final bool joinedByMe;
  final PersonRef? owner;
  const Club({
    required this.id, required this.name, required this.description, required this.category, required this.hue,
    required this.memberCount, required this.joinedByMe, required this.owner, required this.upcomingCount,
  });

  factory Club.fromJson(Map<String, dynamic> j) => Club(
        id: j['id'] as int,
        name: (j['name'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        category: (j['category'] ?? '').toString(),
        hue: ((j['hue'] ?? 150) as num).toInt(),
        memberCount: ((j['memberCount'] ?? 0) as num).toInt(),
        joinedByMe: j['joinedByMe'] == true,
        owner: j['owner'] is Map ? PersonRef.fromJson(Map<String, dynamic>.from(j['owner'])) : null,
        upcomingCount: ((j['upcomingCount'] ?? 0) as num).toInt(),
      );
}

class ClubRef {
  final int id;
  final String name;
  const ClubRef(this.id, this.name);
}
