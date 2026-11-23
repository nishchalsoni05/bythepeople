/// A specific thing a verified foundation is asking donors and other foundations for.
class NeedFoundation {
  final int id;
  final String name;
  final String? orgName;
  final bool verified;
  const NeedFoundation({required this.id, required this.name, this.orgName, this.verified = false});

  factory NeedFoundation.fromJson(Map<String, dynamic> j) => NeedFoundation(
        id: ((j['id'] ?? 0) as num).toInt(),
        name: (j['name'] ?? '').toString(),
        orgName: j['orgName'] as String?,
        verified: j['verified'] == true,
      );

  String get label => (orgName ?? '').isNotEmpty ? orgName! : name;
}

class Need {
  final int id, pledgeCount, createdAt;
  final int? deadlineAt;
  final NeedFoundation foundation;
  final String kind, kindLabel, title, quantity, status;
  final bool pledgedByMe;
  final String urgency, description, unit;
  final int targetQty, pledgedQty;
  final double progress;

  const Need({
    required this.id, required this.foundation, required this.kind, required this.kindLabel, required this.title,
    this.quantity = '', this.deadlineAt, this.status = 'open', this.pledgeCount = 0, this.pledgedByMe = false,
    this.createdAt = 0, this.urgency = 'normal', this.description = '', this.unit = '',
    this.targetQty = 0, this.pledgedQty = 0, this.progress = 0,
  });

  factory Need.fromJson(Map<String, dynamic> j) {
    int? opt(String k) => (j[k] as num?)?.toInt();
    return Need(
      id: ((j['id'] ?? 0) as num).toInt(),
      foundation: NeedFoundation.fromJson(Map<String, dynamic>.from(j['foundation'] ?? const {})),
      kind: (j['kind'] ?? 'other').toString(),
      kindLabel: (j['kindLabel'] ?? 'Other').toString(),
      title: (j['title'] ?? '').toString(),
      quantity: (j['quantity'] ?? '').toString(),
      deadlineAt: opt('deadlineAt'),
      status: (j['status'] ?? 'open').toString(),
      pledgeCount: ((j['pledgeCount'] ?? 0) as num).toInt(),
      pledgedByMe: j['pledgedByMe'] == true,
      createdAt: ((j['createdAt'] ?? 0) as num).toInt(),
      urgency: (j['urgency'] ?? 'normal').toString(),
      description: (j['description'] ?? '').toString(),
      unit: (j['unit'] ?? '').toString(),
      targetQty: ((j['targetQty'] ?? 0) as num).toInt(),
      pledgedQty: ((j['pledgedQty'] ?? 0) as num).toInt(),
      progress: ((j['progress'] ?? 0) as num).toDouble(),
    );
  }

  bool get isOpen => status == 'open';

  /// Sort weight: critical first.
  int get urgencyRank => switch (urgency) { 'critical' => 0, 'high' => 1, 'normal' => 2, _ => 3 };

  bool isOwner(int? meId) => meId != null && foundation.id == meId;
}

/// Filter for the needs board.
const needStatuses = <String>['open', 'closed', 'all'];

/// Body for POST /needs.
class NeedDraft {
  final String kind, title, quantity;
  final int? deadlineAt;
  const NeedDraft({required this.kind, required this.title, this.quantity = '', this.deadlineAt});

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'title': title,
        if (quantity.isNotEmpty) 'quantity': quantity,
        if (deadlineAt != null) 'deadlineAt': deadlineAt,
      };
}
