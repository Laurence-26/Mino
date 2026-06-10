enum GroupRole { admin, editor, viewer }

class Group {
  final String id;
  final String name;
  final String createdBy;
  final DateTime createdAt;
  final Map<String, GroupRole> members;
  final String? inviteCode;

  Group({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    required this.members,
    this.inviteCode,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'members': members.map((key, value) => MapEntry(key, value.name)),
        'inviteCode': inviteCode,
      };

  factory Group.fromMap(String id, Map<String, dynamic> map) => Group(
        id: id,
        name: map['name'] ?? '',
        createdBy: map['createdBy'] ?? '',
        createdAt: DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
        members: (map['members'] as Map<String, dynamic>?)?.map(
              (key, value) => MapEntry(key, GroupRole.values.firstWhere(
                (e) => e.name == value,
                orElse: () => GroupRole.viewer,
              )),
            ) ??
            {},
        inviteCode: map['inviteCode'],
      );
}