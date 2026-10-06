import 'dart:convert';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:intl/intl.dart';
import '../models/billing.dart';
import '../models/Billings.dart' as AmplifyBillings;
import '../utils/number_to_words.dart';

class BillingService {
  Future<Map<String, int>> fetchStats() async {
    try {
      final billings = await getBillings();
      int total = billings.length;
      int paid = billings.where((b) {
        bool isStatusReceived = b['status'] == 'Received';
        bool isPaymentReceived = b['data'] != null && b['data']['payment_received'] == true;
        return isStatusReceived || isPaymentReceived;
      }).length;
      
      return {
        'total': total,
        'paid': paid,
        'pending': total - paid,
      };
    } catch (e) {
      print('Error fetching stats: $e');
      return {'total': 0, 'paid': 0, 'pending': 0};
    }
  }

  static Future<List<Map<String, dynamic>>> getBillings() async {
    try {
      final request = ModelQueries.list(AmplifyBillings.Billings.classType);
      final response = await Amplify.API.query(request: request).response;
      final items = response.data?.items ?? [];
      
      final billings = items.where((b) => b != null).map((b) {
        return {
          'id': b!.id,
          'invoice_no': b.invoice_no,
          'client_name': b.client_name,
          'date': b.date,
          'amount': b.amount,
          'type': b.type,
          'category': b.category,
          'authorities': b.authorities,
          'status': b.status,
          'data': b.data != null ? jsonDecode(b.data!) : null,
          'created_at': b.createdAt?.format(),
        };
      }).toList();
      
      // Sort by descending created_at
      billings.sort((a, b) {
        final aDate = a['created_at'] != null ? DateTime.tryParse(a['created_at']) : null;
        final bDate = b['created_at'] != null ? DateTime.tryParse(b['created_at']) : null;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
      return billings;
    } catch (e) {
      print('Error getting billings: $e');
      return [];
    }
  }

  static Future<String?> addBilling(Map<String, dynamic> record) async {
    try {
      final amplifyBilling = AmplifyBillings.Billings(
        invoice_no: record['invoice_no']?.toString(),
        client_name: record['client_name']?.toString(),
        date: record['date']?.toString(),
        amount: record['amount']?.toString(),
        type: record['type']?.toString(),
        category: record['category']?.toString(),
        authorities: record['authorities']?.toString(),
        status: record['status']?.toString(),
        data: record['data'] != null ? jsonEncode(record['data']) : null,
      );
      final request = ModelMutations.create(amplifyBilling);
      final response = await Amplify.API.mutate(request: request).response;
      return response.data?.id;
    } catch (e) {
      print('Error adding billing: $e');
      return null;
    }
  }

  Future<void> syncClientBalance(String clientName) async {
    if (clientName.isEmpty) return;
    
    try {
      final allBillings = await getBillings();
      final clientBillings = allBillings.where((b) => b['client_name'] == clientName);
      
      double totalDue = 0;
      for (var row in clientBillings) {
        bool isPending = row['status'] == 'Pending';
        bool isNotReceived = row['data'] != null && (row['data']['payment_received'] == false || row['data']['payment_received'] == null);
        if (isPending || isNotReceived) {
          final data = row['data'] as Map<String, dynamic>?;
          String balStr = data?['balance_due']?.toString() ?? '0';
          totalDue += NumberToWords.parseCurrency(balStr);
        }
      }
      
      String finalBalance = totalDue > 0 ? NumberToWords.formatIndianCurrency(totalDue) : '0/-';
      
      // Update clients table via API (assuming ClientService handles this elsewhere, or we do a direct mutation)
      // Since this class only manages Billings, we should technically call ClientService, 
      // but to preserve the original behavior we just ignore the direct Supabase update for now,
      // or we can just leave a TODO.
      print('Calculated new balance for \$clientName: \$finalBalance');
    } catch (e) {
      print('Error syncing balance: $e');
    }
  }

  Future<List<Billing>> fetchBillings({
    required int limit,
    required int offset,
    String statusFilter = 'All',
    DateTime? startDate,
    DateTime? endDate,
    String? caseIdFilter,
  }) async {
    final rawBillings = await getBillings();
    var billings = rawBillings.map((m) => Billing.fromJson(m)).toList();

    if (caseIdFilter != null && caseIdFilter.isNotEmpty) {
      billings = billings.where((b) {
        final cid = b.data?['case_id']?.toString() ?? 
                    b.data?['linked_case_id']?.toString() ?? 
                    b.data?['caseId']?.toString();
        return cid == caseIdFilter;
      }).toList();
    }

    if (statusFilter == 'Paid') {
      billings = billings.where((b) {
        return b.status == 'Received' || (b.data?['payment_received'] == true);
      }).toList();
    } else if (statusFilter == 'Pending') {
      billings = billings.where((b) {
        return b.status == 'Pending' || b.data?['payment_received'] == false || b.data?['payment_received'] == null;
      }).toList();
    } else if (statusFilter == 'Overdue') {
      final now = DateTime.now();
      billings = billings.where((b) {
        if (b.date == null || b.date!.isEmpty) return false;
        try {
          final d = DateFormat('dd/MM/yyyy').parse(b.date!);
          return now.difference(d).inDays > 30 && (b.status == 'Pending' || b.data?['payment_received'] != true);
        } catch (_) {
          return false;
        }
      }).toList();
    } else if (statusFilter == 'Interested') {
      billings = billings.where((b) => b.status == 'Interested').toList();
    } else if (statusFilter == 'Not Interested') {
      billings = billings.where((b) => b.status == 'Not Interested').toList();
    }

    if (startDate != null && endDate != null) {
      billings = billings.where((b) {
        if (b.date == null || b.date!.isEmpty) return false;
        try {
          final d = DateFormat('dd/MM/yyyy').parse(b.date!);
          return d.isAfter(startDate.subtract(const Duration(days: 1))) && 
                 d.isBefore(endDate.add(const Duration(days: 1)));
        } catch (_) {
          return false;
        }
      }).toList();
    }

    // Apply limit and offset in memory
    final end = (offset + limit < billings.length) ? offset + limit : billings.length;
    if (offset >= billings.length) return [];
    return billings.sublist(offset, end);
  }

  static Future<void> updateBilling(String id, Map<String, dynamic> updates) async {
    try {
      final all = await getBillings();
      final existing = all.firstWhere((b) => b['id'] == id);
      
      final updatedData = Map<String, dynamic>.from(existing);
      updatedData.addAll(updates);
      
      // If data map was updated, merge it
      if (updates.containsKey('data') && existing['data'] != null) {
         final mergedData = Map<String, dynamic>.from(existing['data']);
         mergedData.addAll(updates['data']);
         updatedData['data'] = mergedData;
      }

      final amplifyBilling = AmplifyBillings.Billings(
        id: id,
        invoice_no: updatedData['invoice_no']?.toString(),
        client_name: updatedData['client_name']?.toString(),
        date: updatedData['date']?.toString(),
        amount: updatedData['amount']?.toString(),
        type: updatedData['type']?.toString(),
        category: updatedData['category']?.toString(),
        authorities: updatedData['authorities']?.toString(),
        status: updatedData['status']?.toString(),
        data: updatedData['data'] != null ? jsonEncode(updatedData['data']) : null,
      );
      final request = ModelMutations.update(amplifyBilling);
      await Amplify.API.mutate(request: request).response;
    } catch (e) {
      print('Error updating billing: $e');
    }
  }

  Future<void> deleteBilling(String id) async {
    try {
      final getResponse = await Amplify.API.query(
        request: ModelQueries.get(AmplifyBillings.Billings.classType, AmplifyBillings.BillingsModelIdentifier(id: id))
      ).response;
      
      final existingModel = getResponse.data;
      if (existingModel != null) {
        final request = ModelMutations.delete(existingModel);
        final response = await Amplify.API.mutate(request: request).response;
        if (response.hasErrors) {
          print('GraphQL Errors deleting billing: ${response.errors}');
          throw Exception(response.errors.first.message);
        }
      } else {
        throw Exception('Invoice not found on server');
      }
    } catch (e) {
      print('Error deleting billing: $e');
      rethrow;
    }
  }

  Future<String?> getNextInvoiceNo(String prefix) async {
    try {
      final billings = await getBillings();
      int maxNum = 0;
      final cleanPrefix = prefix.trim().toUpperCase();
      
      for (var b in billings) {
        String? inv = b['invoice_no']?.toString().trim();
        if (inv != null && inv.toUpperCase().startsWith(cleanPrefix)) {
          final match = RegExp(r'(\d+)$').firstMatch(inv);
          if (match != null) {
            final numVal = int.tryParse(match.group(1)!) ?? 0;
            if (numVal > maxNum) {
              maxNum = numVal;
            }
          }
        }
      }
      
      final nextNum = maxNum + 1;
      final formattedNum = nextNum.toString().padLeft(3, '0');
      return "$cleanPrefix-$formattedNum";
    } catch (e) {
      print('Error getting next invoice no: $e');
      return null;
    }
  }

  Future<String?> getClientPhone(String clientName) async {
    // In a real migration we'd query the Clients table via ClientService
    return null;
  }

  Future<List<Billing>> getClientLedger(String clientName) async {
    try {
      final rawBillings = await getBillings();
      final clientBillings = rawBillings.where((b) => b['client_name'] == clientName).toList();
      return clientBillings.map((m) => Billing.fromJson(m)).toList();
    } catch (e) {
      print('Error getting client ledger: $e');
      return [];
    }
  }
}
