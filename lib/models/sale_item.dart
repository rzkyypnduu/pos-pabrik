class SaleItem {
  final int? id;
  final int saleId;
  final int? productId;
  final String name;
  final double qty;
  final int price;
  final String? createdAt;
  final String? updatedAt;

  SaleItem({
    this.id,
    required this.saleId,
    this.productId,
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
      'sale_id': saleId,
      'product_id': productId,
      'name': name,
      'qty': qty,
      'price': price,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    return SaleItem(
      id: map['id'] as int?,
      saleId: (map['sale_id'] as num?)?.toInt() ?? 0,
      productId: (map['product_id'] as num?)?.toInt(),
      name: map['name'] as String? ?? '',
      qty: (map['qty'] as num?)?.toDouble() ?? 0,
      price: (map['price'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }
}
