import 'package:freezed_annotation/freezed_annotation.dart';

part 'inventory_response.freezed.dart';
part 'inventory_response.g.dart';

@freezed
class InventoryResponse with _$InventoryResponse {
  const factory InventoryResponse({
    required int inventoryId,
    required String uuid,
    required String name,
    required int quantity,
    required String price,
    required bool isDeleted,          // ✅ added
    required DateTime updatedAt,      // ✅ added
  }) = _InventoryResponse;

  factory InventoryResponse.fromJson(Map<String, dynamic> json) =>
      _$InventoryResponseFromJson(json);
}
