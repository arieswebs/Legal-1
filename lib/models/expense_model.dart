enum ExpenseStatus {
  pending,
  approved,
  rejected,
}

enum TransactionType {
  income,
  expense,
}

class ExpenseModel {
  final String id;
  final String title;
  final double amount;
  final String category;
  final DateTime date;
  final String description;
  final ExpenseStatus status;
  final String submittedBy;
  final TransactionType type;
  final String? linkedCaseId;
  final String? linkedClientName;

  ExpenseModel({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.description,
    required this.status,
    required this.submittedBy,
    required this.type,
    this.linkedCaseId,
    this.linkedClientName,
  });

  ExpenseModel copyWith({
    String? id,
    String? title,
    double? amount,
    String? category,
    DateTime? date,
    String? description,
    ExpenseStatus? status,
    String? submittedBy,
    TransactionType? type,
    String? linkedCaseId,
    String? linkedClientName,
  }) {
    return ExpenseModel(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      date: date ?? this.date,
      description: description ?? this.description,
      status: status ?? this.status,
      submittedBy: submittedBy ?? this.submittedBy,
      type: type ?? this.type,
      linkedCaseId: linkedCaseId ?? this.linkedCaseId,
      linkedClientName: linkedClientName ?? this.linkedClientName,
    );
  }

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      category: json['category']?.toString() ?? '',
      date: json['date'] != null ? DateTime.parse(json['date'].toString()) : DateTime.now(),
      description: json['description']?.toString() ?? '',
      status: ExpenseStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => ExpenseStatus.pending,
      ),
      submittedBy: json['submitted_by']?.toString() ?? '',
      type: TransactionType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => TransactionType.expense,
      ),
      linkedCaseId: json['linked_case_id']?.toString() ?? json['case_id']?.toString() ?? json['caseId']?.toString(),
      linkedClientName: json['linked_client_name']?.toString() ?? json['client_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'category': category,
      'date': date.toIso8601String(),
      'description': description,
      'status': status.toString().split('.').last,
      'submitted_by': submittedBy,
      'type': type.toString().split('.').last,
      if (linkedCaseId != null) 'linked_case_id': linkedCaseId,
      if (linkedClientName != null) 'linked_client_name': linkedClientName,
    };
  }
}
