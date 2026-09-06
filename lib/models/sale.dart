class Sale {
  final int? id;
  final String date;
  final String name;
  final int rawTotal;
  final int roundedTotal;
  final int paid;
  final int diff;
  final String? note;
  final bool isPaidBtnClicked;
  final bool debtPaid;
  final int debtPaidAmount;
  final String? createdAt;
  final String? updatedAt;

  Sale({
    this.id,
    required this.date,
    required this.name,
    this.rawTotal = 0,
    this.roundedTotal = 0,
    this.paid = 0,
    this.diff = 0,
    this.note,
    this.isPaidBtnClicked = false,
    this.debtPaid = false,
    this.debtPaidAmount = 0,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'name': name,
      'raw_total': rawTotal,
      'rounded_total': roundedTotal,
      'paid': paid,
      'diff': diff,
      'note': note,
      'is_paid_btn_clicked': isPaidBtnClicked ? 1 : 0,
      'debt_paid': debtPaid ? 1 : 0,
      'debt_paid_amount': debtPaidAmount,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map) {
    return Sale(
      id: map['id'] as int?,
      date: map['date'] as String? ?? '',
      name: map['name'] as String? ?? '',
      rawTotal: (map['raw_total'] as num?)?.toInt() ?? 0,
      roundedTotal: (map['rounded_total'] as num?)?.toInt() ?? 0,
      paid: (map['paid'] as num?)?.toInt() ?? 0,
      diff: (map['diff'] as num?)?.toInt() ?? 0,
      note: map['note'] as String?,
      isPaidBtnClicked: (map['is_paid_btn_clicked'] as num?)?.toInt() == 1,
      debtPaid: (map['debt_paid'] as num?)?.toInt() == 1,
      debtPaidAmount: (map['debt_paid_amount'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }

  Sale copyWith({
    int? id,
    String? date,
    String? name,
    int? rawTotal,
    int? roundedTotal,
    int? paid,
    int? diff,
    String? note,
    bool? isPaidBtnClicked,
    bool? debtPaid,
    int? debtPaidAmount,
  }) {
    return Sale(
      id: id ?? this.id,
      date: date ?? this.date,
      name: name ?? this.name,
      rawTotal: rawTotal ?? this.rawTotal,
      roundedTotal: roundedTotal ?? this.roundedTotal,
      paid: paid ?? this.paid,
      diff: diff ?? this.diff,
      note: note ?? this.note,
      isPaidBtnClicked: isPaidBtnClicked ?? this.isPaidBtnClicked,
      debtPaid: debtPaid ?? this.debtPaid,
      debtPaidAmount: debtPaidAmount ?? this.debtPaidAmount,
    );
  }
}
