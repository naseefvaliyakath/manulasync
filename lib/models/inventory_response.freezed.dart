// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'inventory_response.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

InventoryResponse _$InventoryResponseFromJson(Map<String, dynamic> json) {
  return _InventoryResponse.fromJson(json);
}

/// @nodoc
mixin _$InventoryResponse {
  int get inventoryId => throw _privateConstructorUsedError;
  String get uuid => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  int get quantity => throw _privateConstructorUsedError;
  String get price => throw _privateConstructorUsedError;
  bool get isDeleted => throw _privateConstructorUsedError; // ✅ added
  DateTime get updatedAt => throw _privateConstructorUsedError;

  /// Serializes this InventoryResponse to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of InventoryResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $InventoryResponseCopyWith<InventoryResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $InventoryResponseCopyWith<$Res> {
  factory $InventoryResponseCopyWith(
    InventoryResponse value,
    $Res Function(InventoryResponse) then,
  ) = _$InventoryResponseCopyWithImpl<$Res, InventoryResponse>;
  @useResult
  $Res call({
    int inventoryId,
    String uuid,
    String name,
    int quantity,
    String price,
    bool isDeleted,
    DateTime updatedAt,
  });
}

/// @nodoc
class _$InventoryResponseCopyWithImpl<$Res, $Val extends InventoryResponse>
    implements $InventoryResponseCopyWith<$Res> {
  _$InventoryResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of InventoryResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? inventoryId = null,
    Object? uuid = null,
    Object? name = null,
    Object? quantity = null,
    Object? price = null,
    Object? isDeleted = null,
    Object? updatedAt = null,
  }) {
    return _then(
      _value.copyWith(
            inventoryId: null == inventoryId
                ? _value.inventoryId
                : inventoryId // ignore: cast_nullable_to_non_nullable
                      as int,
            uuid: null == uuid
                ? _value.uuid
                : uuid // ignore: cast_nullable_to_non_nullable
                      as String,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            quantity: null == quantity
                ? _value.quantity
                : quantity // ignore: cast_nullable_to_non_nullable
                      as int,
            price: null == price
                ? _value.price
                : price // ignore: cast_nullable_to_non_nullable
                      as String,
            isDeleted: null == isDeleted
                ? _value.isDeleted
                : isDeleted // ignore: cast_nullable_to_non_nullable
                      as bool,
            updatedAt: null == updatedAt
                ? _value.updatedAt
                : updatedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$InventoryResponseImplCopyWith<$Res>
    implements $InventoryResponseCopyWith<$Res> {
  factory _$$InventoryResponseImplCopyWith(
    _$InventoryResponseImpl value,
    $Res Function(_$InventoryResponseImpl) then,
  ) = __$$InventoryResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    int inventoryId,
    String uuid,
    String name,
    int quantity,
    String price,
    bool isDeleted,
    DateTime updatedAt,
  });
}

/// @nodoc
class __$$InventoryResponseImplCopyWithImpl<$Res>
    extends _$InventoryResponseCopyWithImpl<$Res, _$InventoryResponseImpl>
    implements _$$InventoryResponseImplCopyWith<$Res> {
  __$$InventoryResponseImplCopyWithImpl(
    _$InventoryResponseImpl _value,
    $Res Function(_$InventoryResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of InventoryResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? inventoryId = null,
    Object? uuid = null,
    Object? name = null,
    Object? quantity = null,
    Object? price = null,
    Object? isDeleted = null,
    Object? updatedAt = null,
  }) {
    return _then(
      _$InventoryResponseImpl(
        inventoryId: null == inventoryId
            ? _value.inventoryId
            : inventoryId // ignore: cast_nullable_to_non_nullable
                  as int,
        uuid: null == uuid
            ? _value.uuid
            : uuid // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        quantity: null == quantity
            ? _value.quantity
            : quantity // ignore: cast_nullable_to_non_nullable
                  as int,
        price: null == price
            ? _value.price
            : price // ignore: cast_nullable_to_non_nullable
                  as String,
        isDeleted: null == isDeleted
            ? _value.isDeleted
            : isDeleted // ignore: cast_nullable_to_non_nullable
                  as bool,
        updatedAt: null == updatedAt
            ? _value.updatedAt
            : updatedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$InventoryResponseImpl implements _InventoryResponse {
  const _$InventoryResponseImpl({
    required this.inventoryId,
    required this.uuid,
    required this.name,
    required this.quantity,
    required this.price,
    required this.isDeleted,
    required this.updatedAt,
  });

  factory _$InventoryResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$InventoryResponseImplFromJson(json);

  @override
  final int inventoryId;
  @override
  final String uuid;
  @override
  final String name;
  @override
  final int quantity;
  @override
  final String price;
  @override
  final bool isDeleted;
  // ✅ added
  @override
  final DateTime updatedAt;

  @override
  String toString() {
    return 'InventoryResponse(inventoryId: $inventoryId, uuid: $uuid, name: $name, quantity: $quantity, price: $price, isDeleted: $isDeleted, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$InventoryResponseImpl &&
            (identical(other.inventoryId, inventoryId) ||
                other.inventoryId == inventoryId) &&
            (identical(other.uuid, uuid) || other.uuid == uuid) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.quantity, quantity) ||
                other.quantity == quantity) &&
            (identical(other.price, price) || other.price == price) &&
            (identical(other.isDeleted, isDeleted) ||
                other.isDeleted == isDeleted) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    inventoryId,
    uuid,
    name,
    quantity,
    price,
    isDeleted,
    updatedAt,
  );

  /// Create a copy of InventoryResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$InventoryResponseImplCopyWith<_$InventoryResponseImpl> get copyWith =>
      __$$InventoryResponseImplCopyWithImpl<_$InventoryResponseImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$InventoryResponseImplToJson(this);
  }
}

abstract class _InventoryResponse implements InventoryResponse {
  const factory _InventoryResponse({
    required final int inventoryId,
    required final String uuid,
    required final String name,
    required final int quantity,
    required final String price,
    required final bool isDeleted,
    required final DateTime updatedAt,
  }) = _$InventoryResponseImpl;

  factory _InventoryResponse.fromJson(Map<String, dynamic> json) =
      _$InventoryResponseImpl.fromJson;

  @override
  int get inventoryId;
  @override
  String get uuid;
  @override
  String get name;
  @override
  int get quantity;
  @override
  String get price;
  @override
  bool get isDeleted; // ✅ added
  @override
  DateTime get updatedAt;

  /// Create a copy of InventoryResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$InventoryResponseImplCopyWith<_$InventoryResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
