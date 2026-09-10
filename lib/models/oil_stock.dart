class OilStock {
  final int? id;
  final String? date;
  final double qty;
  final double price;
  final String? createdAt;
  final String? updatedAt;

  OilStock({
    this.id,
    this.date,
    this.qty = 0,
    this.price = 0,
    this.createdAt,
    this.updatedAt,
  });

  int get subtotal => (qty * price).round();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'qty': qty,
      'price': price,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory OilStock.fromMap(Map<String, dynamic> map) {
    return OilStock(
      id: map['id'] as int?,
      date: map['date'] as String?,
      qty: (map['qty'] as num?)?.toDouble() ?? 0,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }
}
