class CustomerDailyBalance {
  final int? id;
  final String date;
  final String name;
  final int amount;

  CustomerDailyBalance({
    this.id,
    required this.date,
    required this.name,
    required this.amount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'name': name,
      'amount': amount,
    };
  }

  factory CustomerDailyBalance.fromMap(Map<String, dynamic> map) {
    return CustomerDailyBalance(
      id: map['id'] as int?,
      date: map['date'] as String? ?? '',
      name: map['name'] as String? ?? '',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
    );
  }
}