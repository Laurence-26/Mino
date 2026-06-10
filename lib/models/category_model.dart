class Category {
  final String id;
  final String name;
  final bool isIncome; // true for income, false for expense
  final String? iconName;
  final String? colorHex;

  Category({
    required this.id,
    required this.name,
    required this.isIncome,
    this.iconName,
    this.colorHex,
  });

  factory Category.fromFirestore(String id, Map<String, dynamic> data) {
    return Category(
      id: id,
      name: data['name'],
      isIncome: data['isIncome'],
      iconName: data['iconName'],
      colorHex: data['colorHex'],
    );
  }
}