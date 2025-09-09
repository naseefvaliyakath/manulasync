import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/api_response.dart';
import '../models/inventory_response.dart';

class ApiService {
  final String baseUrl;

  ApiService({required this.baseUrl});

  // 🔹 Single sync
  Future<ApiResponse<InventoryResponse>> singleSyncInventory(
      Map<String, dynamic> item) async {
    final response = await http.post(
      Uri.parse('$baseUrl/inventory'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(item),
    );

    final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;

    return ApiResponse.fromJson(
      jsonResponse,
          (json) => InventoryResponse.fromJson(json as Map<String, dynamic>),
    );
  }

  // 🔹 Batch sync
  Future<ApiResponse<List<InventoryResponse>>> batchSyncInventory(
      List<Map<String, dynamic>> items) async {
    final response = await http.post(
      Uri.parse('$baseUrl/inventory/batch'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'items': items}),
    );

    final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;

    return ApiResponse.fromJson(
      jsonResponse,
          (json) {
        // ✅ Expecting {"processedItems": [...], "errors": [...]}
        final map = json as Map<String, dynamic>;
        final list = (map['processedItems'] as List)
            .map((e) => InventoryResponse.fromJson(e as Map<String, dynamic>))
            .toList();
        return list;
      },
    );
  }


// 🔹 Downstream sync (fetch changes from server since last sync)
  Future<ApiResponse<List<InventoryResponse>>> fetchServerChanges(String since) async {
    final uri = Uri.parse('$baseUrl/inventory/changes').replace(
      queryParameters: {'since': since},
    );

    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    );

    final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;

    return ApiResponse.fromJson(
      jsonResponse,
          (data) {
        final map = data as Map<String, dynamic>;
        final list = (map['changes'] as List)
            .map((e) => InventoryResponse.fromJson(e as Map<String, dynamic>))
            .toList();
        return list;
      },
    );
  }

}
