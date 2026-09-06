class CustomerLedger {
  final int? id;
  final String date;
  final String name;
  final int amount;
  final String type; // 'tambah' or 'bayar'
  final String? note;
  final int? saleId;
  final String? createdAt;
  final String? updatedAt;

  CustomerLedger({
    this.id,
    required this.date,
    required this.name,
    required this.amount,
    required this.type,
    this.note,
    this.saleId,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'name': name,
      'amount': amount,
      'type': type,
      'note': note,
      'sale_id': saleId,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory CustomerLedger.fromMap(Map<String, dynamic> map) {
    return CustomerLedger(
      id: map['id'] as int?,
      date: map['date'] as String? ?? '',
      name: map['name'] as String? ?? '',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      type: map['type'] as String? ?? 'tambah',
      note: map['note'] as String?,
      saleId: (map['sale_id'] as num?)?.toInt(),
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }

  CustomerLedger copyWith({
    int? id,
    String? date,
    String? name,
    int? amount,
    String? type,
    String? note,
    int? saleId,
  }) {
    return CustomerLedger(
      id: id ?? this.id,
      date: date ?? this.date,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      note: note ?? this.note,
      saleId: saleId ?? this.saleId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
