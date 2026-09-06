class PersonalLedger {
  final int? id;
  final String date;
  final String name;
  final int amount;
  final String? note;
  final String? createdAt;
  final String? updatedAt;

  PersonalLedger({
    this.id,
    required this.date,
    required this.name,
    required this.amount,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'name': name,
      'amount': amount,
      'note': note,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory PersonalLedger.fromMap(Map<String, dynamic> map) {
    return PersonalLedger(
      id: map['id'] as int?,
      date: map['date'] as String? ?? '',
      name: map['name'] as String? ?? '',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      note: map['note'] as String?,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }
}
