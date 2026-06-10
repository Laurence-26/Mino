class AppUser {
  final String uid;
  final String phone;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final DateTime createdAt;
  final List<String> groupIds;

  AppUser({
    required this.uid,
    required this.phone,      // can be empty string for anonymous
    required this.email,      // can be empty string
    this.displayName,
    this.photoUrl,
    required this.createdAt,
    this.groupIds = const [],
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'phone': phone,
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'createdAt': createdAt.toIso8601String(),
        'groupIds': groupIds,
      };

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        uid: map['uid'] ?? '',
        phone: map['phone'] ?? '',
        email: map['email'] ?? '',
        displayName: map['displayName'],
        photoUrl: map['photoUrl'],
        createdAt: map['createdAt'] != null
            ? DateTime.parse(map['createdAt'])
            : DateTime.now(),
        groupIds: List<String>.from(map['groupIds'] ?? []),
      );

  String get name => displayName ?? 'User';
}