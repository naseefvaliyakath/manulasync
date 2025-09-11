import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/api_response.dart';
import '../models/inventory_response.dart';
import '../models/category_response.dart';

class ApiService {
  final String baseUrl;

  ApiService({required this.baseUrl});

  // 🔹 Generic batch sync for any table and response model
  Future<ApiResponse<List<T>>> batchSyncGeneric<T>({
    required String tablePath, // e.g., 'inventory', 'categories'
    required List<Map<String, dynamic>> items,
    required T Function(Map<String, dynamic>) itemFromJson,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/$tablePath/batch'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'items': items}),
    );

    final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;

    return ApiResponse.fromJson(jsonResponse, (data) {
      final map = data as Map<String, dynamic>;
      final list = (map['processedItems'] as List)
          .map((e) => itemFromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    });
  }

  // 🔹 Generic fetch changes for any table
  Future<ApiResponse<List<T>>> fetchServerChangesGeneric<T>({
    required String tablePath, // e.g., 'inventory', 'categories'
    required String since,
    required T Function(Map<String, dynamic>) itemFromJson,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/$tablePath/changes',
    ).replace(queryParameters: {'since': since});

    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    );

    final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;

    return ApiResponse.fromJson(jsonResponse, (data) {
      final map = data as Map<String, dynamic>;
      final list = (map['changes'] as List)
          .map((e) => itemFromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    });
  }
}
