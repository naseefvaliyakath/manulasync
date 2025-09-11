// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CategoryResponseImpl _$$CategoryResponseImplFromJson(
  Map<String, dynamic> json,
) => _$CategoryResponseImpl(
  categoryId: (json['categoryId'] as num).toInt(),
  uuid: json['uuid'] as String,
  name: json['name'] as String,
  isDeleted: json['isDeleted'] as bool,
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  serverId: json['serverId'] as String,
);

Map<String, dynamic> _$$CategoryResponseImplToJson(
  _$CategoryResponseImpl instance,
) => <String, dynamic>{
  'categoryId': instance.categoryId,
  'uuid': instance.uuid,
  'name': instance.name,
  'isDeleted': instance.isDeleted,
  'updatedAt': instance.updatedAt.toIso8601String(),
  'serverId': instance.serverId,
};
