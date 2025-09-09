// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$InventoryResponseImpl _$$InventoryResponseImplFromJson(
  Map<String, dynamic> json,
) => _$InventoryResponseImpl(
  inventoryId: (json['inventoryId'] as num).toInt(),
  uuid: json['uuid'] as String,
  name: json['name'] as String,
  quantity: (json['quantity'] as num).toInt(),
  price: json['price'] as String,
  isDeleted: json['isDeleted'] as bool,
  updatedAt: DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$$InventoryResponseImplToJson(
  _$InventoryResponseImpl instance,
) => <String, dynamic>{
  'inventoryId': instance.inventoryId,
  'uuid': instance.uuid,
  'name': instance.name,
  'quantity': instance.quantity,
  'price': instance.price,
  'isDeleted': instance.isDeleted,
  'updatedAt': instance.updatedAt.toIso8601String(),
};
