import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';
import '../models/Cases.dart';
import 'dart:convert';

class CaseService {
  /// Helper to convert Cases model to Map<String, dynamic>
  static Map<String, dynamic> _toMap(Cases caseObj) {
    // We merge the strongly typed fields and the generic 'data' json field
    final map = caseObj.toJson();
    if (caseObj.data != null) {
      try {
        final dataMap = jsonDecode(caseObj.data!) as Map<String, dynamic>;
        map.addAll(dataMap);
      } catch (_) {}
    }
    // Also alias id
    map['id'] = caseObj.id;
    return map;
  }

  /// Fetch all cases
  static Future<List<Map<String, dynamic>>> getCases() async {
    try {
      final request = ModelQueries.list(Cases.classType);
      final response = await Amplify.API.query(request: request).response;
      
      if (response.hasErrors) {
        print('Error fetching cases from Amplify: ${response.errors}');
        return [];
      }
      
      final cases = response.data?.items ?? [];
      // Sort by createdAt descending
      cases.sort((a, b) {
        if (a?.createdAt == null || b?.createdAt == null) return 0;
        return b!.createdAt!.compareTo(a!.createdAt!);
      });
      
      final casesToReturn = cases.whereType<Cases>().map((e) => _toMap(e)).toList();
      
      // Auto-backfill for cases that are missing created_by (so the user doesn't see Unknown)
      for (var c in casesToReturn) {
        if (c['created_by'] == null || c['created_by'] == 'Unknown' || c['created_by'].toString().trim().isEmpty) {
           c['created_by'] = 'System';
        }
      }
      return casesToReturn;
    } catch (e) {
      print('Error fetching cases: $e');
      return [];
    }
  }

  /// Fetch cases where the assignee is in responsible_staff
  static Future<List<Map<String, dynamic>>> getCasesByAssignee(String assignee) async {
    try {
      final allCases = await getCases();
      return allCases.where((c) {
        final staff = c['responsible_staff'];
        if (staff is List) {
          return staff.any((s) => s.toString().contains(assignee));
        } else if (staff is String) {
          return staff.contains(assignee);
        }
        return false;
      }).toList();
    } catch (e) {
      print('Error fetching cases for assignee: $e');
      return [];
    }
  }

  /// Fetch cases belonging to a specific client
  static Future<List<Map<String, dynamic>>> getCasesByClient(String clientName) async {
    try {
      final allCases = await getCases();
      final lowerName = clientName.toLowerCase();
      
      return allCases.where((c) {
        final cName = (c['client_name'] ?? '').toString().trim().toLowerCase();
        return cName.isNotEmpty && cName == lowerName.trim();
      }).toList();
    } catch (e) {
      print('Error fetching cases for client: $e');
      return [];
    }
  }

  /// Add a new case
  static Future<void> addCase(Map<String, dynamic> caseData) async {
    try {
      // Gather all fields that are not explicitly mapped
      final knownKeys = ['case_title', 'case_number', 'status', 'court_details', 'next_hearing_date', 'data'];
      final arbitraryData = <String, dynamic>{};
      
      // If there is existing data in 'data' field, start with that
      if (caseData['data'] != null && caseData['data'] is Map) {
        arbitraryData.addAll(caseData['data'] as Map<String, dynamic>);
      }
      
      // Add any unmapped root fields to the arbitrary data
      caseData.forEach((key, value) {
        if (!knownKeys.contains(key) && value != null) {
          arbitraryData[key] = value;
        }
      });

      final newCase = Cases(
        title: caseData['case_title']?.toString(),
        case_number: caseData['case_number']?.toString(),
        status: caseData['status']?.toString(),
        court_details: caseData['court_details']?.toString(),
        next_hearing_date: caseData['next_hearing_date']?.toString(),
        data: arbitraryData.isNotEmpty ? jsonEncode(arbitraryData) : null,
      );
      
      final request = ModelMutations.create(newCase);
      final response = await Amplify.API.mutate(request: request).response;
      
      if (response.hasErrors) {
        throw Exception(response.errors.first.message);
      }
    } catch (e) {
      print('Error adding case: $e');
      rethrow;
    }
  }

  /// Update an existing case
  static Future<void> updateCase(String id, Map<String, dynamic> updates) async {
    try {
      // First get the case
      final getReq = ModelQueries.get(Cases.classType, CasesModelIdentifier(id: id));
      final getRes = await Amplify.API.query(request: getReq).response;
      final existingCase = getRes.data;
      
      if (existingCase != null) {
        // Merge arbitrary data
        Map<String, dynamic> currentData = {};
        if (existingCase.data != null) {
          try {
            currentData = jsonDecode(existingCase.data!) as Map<String, dynamic>;
          } catch (_) {}
        }
        currentData.addAll(updates);
        
        final updatedCase = existingCase.copyWith(
          title: updates['case_title']?.toString() ?? existingCase.title,
          case_number: updates['case_number']?.toString() ?? existingCase.case_number,
          status: updates['status']?.toString() ?? existingCase.status,
          court_details: updates['court_details']?.toString() ?? existingCase.court_details,
          next_hearing_date: updates['next_hearing_date']?.toString() ?? existingCase.next_hearing_date,
          data: currentData.isNotEmpty ? jsonEncode(currentData) : existingCase.data,
        );
        
        final request = ModelMutations.update(updatedCase);
        await Amplify.API.mutate(request: request).response;
      }
    } catch (e) {
      print('Error updating case: $e');
    }
  }

  /// Delete a case
  static Future<void> deleteCase(String id) async {
    try {
      // Fetch full model first to get _version metadata
      final getRequest = ModelQueries.get(
        Cases.classType,
        CasesModelIdentifier(id: id),
      );
      final getResponse = await Amplify.API.query(request: getRequest).response;
      final existingCase = getResponse.data;

      if (existingCase != null) {
        final deleteRequest = ModelMutations.delete(existingCase);
        final response = await Amplify.API.mutate(request: deleteRequest).response;
        if (response.hasErrors) {
          throw Exception('GraphQL errors: ${response.errors}');
        }
      }
    } catch (e) {
      print('Error deleting case: $e');
      throw Exception('Failed to delete case: $e');
    }
  }
}
