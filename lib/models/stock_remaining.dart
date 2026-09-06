class StockRemaining {
  final int? id;
  final String? date;
  final String name;
  final double qty;
  final int price;
  final String? createdAt;
  final String? updatedAt;

  StockRemaining({
    this.id,
    this.date,
    required this.name,
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
      'name': name,
      'qty': qty,
      'price': price,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory StockRemaining.fromMap(Map<String, dynamic> map) {
    return StockRemaining(
      id: map['id'] as int?,
      date: map['date'] as String?,
      name: map['name'] as String? ?? '',
      qty: (map['qty'] as num?)?.toDouble() ?? 0,
      price: (map['price'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }
}
