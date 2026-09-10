class SaldoDeduction {
  final int? id;
  final String? date;
  final double a;
  final double b;
  final String? note;
  final String? createdAt;
  final String? updatedAt;

  SaldoDeduction({
    this.id,
    this.date,
    this.a = 0,
    this.b = 0,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  double get result => a - b;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'a': a,
      'b': b,
      'note': note,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory SaldoDeduction.fromMap(Map<String, dynamic> map) {
    return SaldoDeduction(
      id: map['id'] as int?,
      date: map['date'] as String?,
      a: (map['a'] as num?)?.toDouble() ?? 0,
      b: (map['b'] as num?)?.toDouble() ?? 0,
      note: map['note'] as String?,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }
}
