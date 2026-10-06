import 'dart:convert';
import 'dart:io';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';
import '../models/Users.dart' as AmplifyUsers;
import '../utils/display_name_helper.dart';

class UserService {
  static bool _hasAttemptedSeeding = false;

  /// Fetch all users from the users table
  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final request = ModelQueries.list(AmplifyUsers.Users.classType);
      final response = await Amplify.API.query(request: request).response;
      final items = response.data?.items ?? [];
      
      final users = items.where((e) => e != null).map((e) {
        if (e!.data != null) {
          final json = jsonDecode(e.data!);
          json['id'] = e.id;
          json['name'] = DisplayNameHelper.overrideName(json['name']?.toString() ?? '');
          return json;
        } else {
          final data = jsonDecode(e.data ?? '{}');
          final phone = data['phone'] as String?;
          return {
            'id': e.id,
            'email': e.email,
            'role': e.role,
            'name': DisplayNameHelper.overrideName(e.name ?? ''),
            'phone': phone,
            'username': e.username ?? data['username'],
            'is_active': true,
          };
        }
      }).where((u) {
        if (u['is_deleted'] == true) return false;
        final email = (u['email'] ?? '').toString().toLowerCase();
        if (email == 'admin@cuc.com' || email == 'manager@cuc.com' || email == 'staff@cuc.com') return false;
        final name = (u['name'] ?? '').toString().toLowerCase();
        if (name == 'admin' || name == 'manager' || name == 'staff') return false;
        return true;
      }).toList();
      
      users.sort((a, b) => (a['role'] ?? '').compareTo(b['role'] ?? ''));

      if (users.isEmpty && !_hasAttemptedSeeding) {
        _hasAttemptedSeeding = true;
        print('Users table is empty, seeding default staff members...');
        await createUser(email: 'admin@cuc.com', password: 'Cuc@12345', name: 'Admin', role: 'Admin', roleTitle: 'System Administrator', phone: '+1234567890');
        await createUser(email: 'manager@cuc.com', password: 'Cuc@12345', name: 'Manager', role: 'Manager', roleTitle: 'Operations Manager', phone: '+1234567890');
        await createUser(email: 'staff@cuc.com', password: 'Cuc@12345', name: 'Staff', role: 'Staff', roleTitle: 'Paralegal', phone: '+1234567890');
        return await getAllUsers(); // Retry fetching after seeding
      }

      return List<Map<String, dynamic>>.from(users);
    } catch (e) {
      print('Error fetching users: $e');
      return [];
    }
  }

  /// Create a new user account
  static Future<bool> createUser({
    required String email,
    required String password,
    required String role,
    required String name,
    String username = '',
    String phone = '',
    String enrollmentId = 'N/A',
    String roleTitle = '',
    String specialty = 'General Practice',
  }) async {
    try {
      try {
        await Amplify.Auth.signUp(
          username: email.toLowerCase().trim(),
          password: password,
          options: SignUpOptions(
            userAttributes: {
              AuthUserAttributeKey.email: email.toLowerCase().trim(),
              AuthUserAttributeKey.name: name,
            },
          ),
        );
      } catch (authErr) {
        print('Cognito signup info: ${authErr.toString()}');
        final errString = authErr.toString();
        if (!errString.contains('UsernameExistsException') && !errString.contains('LimitExceededException')) {
          print('Failed to create user in Cognito');
          return false;
        }
      }

      final data = {
        'email': email.toLowerCase().trim(),
        'password_hash': password, // Ideally use Amplify Auth instead of custom table
        'role': role,
        'name': name,
        'username': username,
        'phone': phone,
        'enrollment_id': enrollmentId,
        'role_title': roleTitle,
        'specialty': specialty,
        'is_active': true,
      };
      
      final newUser = AmplifyUsers.Users(
        username: username.isEmpty ? email.toLowerCase().trim() : username,
        password: password,
        role: role,
        name: name,
        email: email.toLowerCase().trim(),
        data: jsonEncode(data),
      );

      final request = ModelMutations.create(newUser);
      final response = await Amplify.API.mutate(request: request).response;
      
      if (response.hasErrors) {
        print('GraphQL Errors in createUser: ${response.errors}');
        return false;
      }
      return true;
    } catch (e) {
      print('Error creating user: $e');
      return false;
    }
  }

  /// Update an existing user's details
  static Future<bool> updateUser({
    required String email,
    String? newEmail,
    required String role,
    required String name,
    String? username,
    String phone = '',
    String enrollmentId = 'N/A',
    String roleTitle = '',
    String specialty = 'General Practice',
    String? newPassword,
  }) async {
    try {
      final all = await getAllUsers();
      final target = all.firstWhere((u) => u['email'] == email.toLowerCase().trim(), orElse: () => {});
      if (target.isEmpty) return false;
      
      final targetId = target['id'] as String;
      final updates = Map<String, dynamic>.from(target);
      updates['role'] = role;
      updates['name'] = name;
      if (newEmail != null && newEmail.isNotEmpty) {
        updates['email'] = newEmail.toLowerCase().trim();
      }
      if (username != null) updates['username'] = username;
      updates['phone'] = phone;
      updates['enrollment_id'] = enrollmentId;
      updates['role_title'] = roleTitle;
      updates['specialty'] = specialty;
      
      if (newPassword != null && newPassword.isNotEmpty) {
        updates['password_hash'] = newPassword;
      }
      
      final document = '''
        mutation UpdateUsers(\$input: UpdateUsersInput!) {
          updateUsers(input: \$input) {
            id
          }
        }
      ''';
      
      final variables = {
        'input': {
          'id': targetId,
          'email': (newEmail ?? email).toLowerCase().trim(),
          'name': name,
          'username': username ?? target['username'],
          'role': role,
          'data': jsonEncode(updates)
        }
      };
      
      final request = GraphQLRequest<String>(document: document, variables: variables);
      final response = await Amplify.API.mutate(request: request).response;
      
      try {
        File('d:/Cochin United/Legal/debug_log.txt').writeAsStringSync('GraphQL Update Response Data: ${response.data}\n', mode: FileMode.append);
      } catch(e) {}
      
      if (response.hasErrors) {
        try {
          File('d:/Cochin United/Legal/debug_log.txt').writeAsStringSync('GraphQL Errors: ${response.errors}\n', mode: FileMode.append);
        } catch(e) {}
        throw Exception('GraphQL Error: ${response.errors.first.message}');
      }
      return true;
    } catch (e) {
      print('Error updating user: $e');
      throw Exception('Error: $e');
    }
  }

  /// Toggle active/inactive status
  static Future<bool> setUserActive(String email, bool isActive) async {
    try {
      final all = await getAllUsers();
      final target = all.firstWhere((u) => u['email'] == email.toLowerCase().trim(), orElse: () => {});
      if (target.isEmpty) return false;
      
      final targetId = target['id'] as String;
      final updates = Map<String, dynamic>.from(target);
      updates['is_active'] = isActive;
      
      final document = '''
        mutation UpdateUsers(\$input: UpdateUsersInput!) {
          updateUsers(input: \$input) {
            id
          }
        }
      ''';
      
      final variables = {
        'input': {
          'id': targetId,
          'data': jsonEncode(updates)
        }
      };
      
      final request = GraphQLRequest<String>(document: document, variables: variables);
      final response = await Amplify.API.mutate(request: request).response;
      
      if (response.hasErrors) {
        print('GraphQL Errors in setUserActive: ${response.errors}');
        return false;
      }
      return true;
    } catch (e) {
      print('Error toggling user status: $e');
      return false;
    }
  }

  /// Delete a user by email
  static Future<bool> deleteUser(String email) async {
    try {
      final all = await getAllUsers();
      // Allow searching deleted users too so we can find them if needed
      final target = all.firstWhere((u) => u['email'] == email.toLowerCase().trim(), orElse: () => {});
      if (target.isEmpty) return false;
      
      final targetId = target['id'] as String;
      
      final updates = Map<String, dynamic>.from(target);
      updates['is_deleted'] = true; // Soft delete flag
      
      final document = '''
        mutation UpdateUsers(\$input: UpdateUsersInput!) {
          updateUsers(input: \$input) {
            id
          }
        }
      ''';
      
      final variables = {
        'input': {
          'id': targetId,
          'data': jsonEncode(updates)
        }
      };
      
      final request = GraphQLRequest<String>(document: document, variables: variables);
      final response = await Amplify.API.mutate(request: request).response;
      
      if (response.hasErrors) {
        throw Exception('GraphQL Error: ${response.errors.first.message}');
      }
      return true;
    } catch (e) {
      print('Error deleting user: $e');
      throw Exception('Error: $e');
    }
  }
}
