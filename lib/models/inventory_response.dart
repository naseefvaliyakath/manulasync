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
    required bool isDeleted,
    required DateTime updatedAt,
    required String serverId, // ✅ added serverId field
  }) = _InventoryResponse;

  factory InventoryResponse.fromJson(Map<String, dynamic> json) =>
      _$InventoryResponseFromJson(json);
}
