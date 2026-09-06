class Expense {
  final int? id;
  final String date;
  final int amount;
  final String? note;
  final String? createdAt;
  final String? updatedAt;

  Expense({
    this.id,
    required this.date,
    this.amount = 0,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'amount': amount,
      'note': note,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as int?,
      date: map['date'] as String? ?? '',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      note: map['note'] as String?,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }
}
