import 'dart:convert';

class StockManagement {
  final int? id;
  final String? date;
  final String name;
  final double qty;
  final int price;
  final List<Map<String, dynamic>>? batches;
  final String? createdAt;
  final String? updatedAt;

  StockManagement({
    this.id,
    this.date,
    required this.name,
    this.qty = 0,
    this.price = 0,
    this.batches,
    this.createdAt,
    this.updatedAt,
  });

  double get totalQty {
    if (batches != null && batches!.isNotEmpty) {
      double sum = 0;
      for (final batch in batches!) {
        final sacks = (batch['sacks'] as List?) ?? [];
        sum += sacks.fold<double>(0, (a, b) => a + (b as num).toDouble());
      }
      return sum;
    }
    return qty;
  }

  int get totalValue {
    if (batches != null && batches!.isNotEmpty) {
      int sum = 0;
      for (final batch in batches!) {
        final sacks = (batch['sacks'] as List?) ?? [];
        final batchQty =
            sacks.fold<double>(0, (a, b) => a + (b as num).toDouble());
        final batchPrice = (batch['price'] as num?)?.toInt() ?? price;
        sum += (batchQty * batchPrice).round();
      }
      return sum;
    }
    return (qty * price).round();
  }

  int get subtotal {
    if (batches != null && batches!.isNotEmpty) {
      int sum = 0;
      for (final batch in batches!) {
        final sacks = (batch['sacks'] as List?) ?? [];
        final batchQty =
            sacks.fold<double>(0, (a, b) => a + (b as num).toDouble());
        final batchPrice = (batch['price'] as num?)?.toInt() ?? price;
        sum += (batchQty * batchPrice).round();
      }
      return sum;
    }
    return (qty * price).round();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'name': name,
      'qty': qty,
      'price': price,
      'batches': batches != null ? jsonEncode(batches) : null,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory StockManagement.fromMap(Map<String, dynamic> map) {
    List<Map<String, dynamic>>? parsedBatches;
    if (map['batches'] != null) {
      if (map['batches'] is String) {
        try {
          final decoded = jsonDecode(map['batches'] as String);
          parsedBatches = List<Map<String, dynamic>>.from(
              (decoded as List).map((e) => Map<String, dynamic>.from(e)));
        } catch (_) {
          parsedBatches = [];
        }
      } else if (map['batches'] is List) {
        parsedBatches = List<Map<String, dynamic>>.from(
            (map['batches'] as List).map((e) => Map<String, dynamic>.from(e)));
      }
    }

    return StockManagement(
      id: map['id'] as int?,
      date: map['date'] as String?,
      name: map['name'] as String? ?? '',
      qty: (map['qty'] as num?)?.toDouble() ?? 0,
      price: (map['price'] as num?)?.toInt() ?? 0,
      batches: parsedBatches,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }
}
