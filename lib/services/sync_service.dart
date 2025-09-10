import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/database.dart' as db;
import 'api_service.dart';
import '../utils/network_checker.dart';
import '../models/inventory_response.dart';
import '../models/category_response.dart';
import 'package:drift/drift.dart';

/// Result of processing a server item during sync
enum SyncResult {
  inserted, // New item was inserted
  updated, // Existing item was updated
  skipped, // No changes needed
}

class SyncService {
  final db.AppDatabase _database;
  final ApiService api;
  Timer? _timer;
  VoidCallback? _onDataChanged;

  SyncService({required db.AppDatabase database, required this.api})
    : _database = database;

  void setOnDataChangedCallback(VoidCallback callback) {
    _onDataChanged = callback;
  }

  void startSync({Duration interval = const Duration(seconds: 10)}) {
    _timer = Timer.periodic(interval, (_) {
      batchSyncItems();
      batchSyncCategories();
      pullChangesCategories(); // Pull categories first
      pullChanges(); // Then pull inventory
    });
  }

  DateTime _parseServerDate(dynamic raw) {
    if (raw is DateTime) return raw.toUtc();
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toUtc();
      // handle "yyyy-MM-dd HH:mm:ss[.SSS]" without timezone
      try {
        final parts = raw.split(' ');
        if (parts.length == 2) {
          final d = parts[0].split('-').map(int.parse).toList();
          final tParts = parts[1].split(':');
          final h = int.parse(tParts[0]);
          final m = int.parse(tParts[1]);
          final sStr = tParts.length > 2 ? tParts[2] : '0';
          final s = int.parse(sStr.split('.').first);
          return DateTime.utc(d[0], d[1], d[2], h, m, s);
        }
      } catch (_) {}
    }
    return DateTime.now().toUtc();
  }

  void stopSync() {
    _timer?.cancel();
  }

  /// Automatically creates the right Companion class for any table
  dynamic _createCompanionForTable(String tableName, String serverId) {
    switch (tableName) {
      case 'inventory_items':
        return db.InventoryItemsCompanion(
          isSynced: const Value(true),
          serverId: Value(serverId),
        );
      case 'categories':
        return db.CategoriesCompanion(
          isSynced: const Value(true),
          serverId: Value(serverId),
        );
      default:
        debugPrint('⚠️ Unknown table: $tableName - skipping sync');
        return null;
    }
  }

  /// Optimized generic batch sync with safety mechanisms
  Future<void>
  batchSyncStandardTable<TTable extends Table, TData extends DataClass>({
    required String tablePath,
    required TableInfo<TTable, TData> table,
  }) async {
    try {
      final connected = await NetworkChecker.isConnected;
      if (!connected) return;

      final unsynced =
          await (_database.select(table)
                ..where((t) => (t as dynamic).isSynced.equals(false))
                ..limit(100)) // Prevent memory issues with large datasets
              .get();
      if (unsynced.isEmpty) return;

      final items = unsynced.map((row) {
        final json = (row as dynamic).toJson() as Map<String, dynamic>;
        return json
          ..remove('localId')
          ..remove('serverId')
          ..update(
            'updatedAt',
            (v) => v is DateTime ? v.toUtc().toIso8601String() : v,
          );
      }).toList();

      final resp = await api.batchSyncGeneric<Map<String, dynamic>>(
        tablePath: tablePath,
        items: items,
        itemFromJson: (m) => m,
      );

      if (resp.status != 201 || resp.data == null) {
        debugPrint('Batch sync failed: ${resp.error ?? resp.message}');
        return;
      }

      // Use batch operation for atomicity with automatic Companion creation
      await _database.batch((batch) {
        for (final item in resp.data!) {
          final uuid = item['uuid']?.toString();
          if (uuid == null || uuid.isEmpty) continue;

          final serverId = item['serverId']?.toString();
          if (serverId == null || serverId.isEmpty) continue;

          // Automatically create the right Companion using table name
          final tableName = table.actualTableName;
          final companion = _createCompanionForTable(tableName, serverId);

          if (companion != null) {
            batch.update(
              table,
              companion,
              where: (tbl) => (tbl as dynamic).uuid.equals(uuid),
            );
          }
        }
      });
    } catch (e, st) {
      debugPrint('❌ Batch sync failed: $e\n$st');
      // Don't rethrow - let sync continue on next interval
    }
  }

  Future<void> batchSyncItems() async {
    return batchSyncStandardTable<Table, db.InventoryItem>(
      tablePath: 'inventory',
      table: _database.inventoryItems,
    );
  }

  Future<void> batchSyncCategories() async {
    return batchSyncStandardTable<Table, db.Category>(
      tablePath: 'categories',
      table: _database.categories,
    );
  }

  /// Process a single server item with comprehensive conflict resolution old
  // Future<void> pullChanges() async {
  //   try {
  //     final apiResponse = await api.fetchServerChanges(
  //       '2025-09-02T18:00:00.000Z',
  //     );
  //     if (apiResponse.status != 200 || apiResponse.data?.isEmpty != false)
  //       return;
  //
  //     bool hasChanges = false;
  //     for (final serverItem in apiResponse.data!) {
  //       try {
  //         final result = await _processServerItem(serverItem);
  //         hasChanges =
  //             hasChanges ||
  //             result == SyncResult.inserted ||
  //             result == SyncResult.updated;
  //       } catch (_) {}
  //     }
  //
  //     if (hasChanges) _onDataChanged?.call();
  //   } catch (_) {}
  // }
  //
  // Future<SyncResult> _processServerItem(InventoryResponse serverItem) async {
  //   final serverUpdatedAt = _parseServerDate(serverItem.updatedAt).toUtc();
  //   final existingItem = await (_database.select(
  //     _database.inventoryItems,
  //   )..where((tbl) => tbl.uuid.equals(serverItem.uuid))).getSingleOrNull();
  //
  //   if (serverItem.isDeleted) {
  //     if (existingItem != null)
  //       await (_database.delete(
  //         _database.inventoryItems,
  //       )..where((tbl) => tbl.uuid.equals(serverItem.uuid))).go();
  //     return existingItem != null ? SyncResult.updated : SyncResult.skipped;
  //   }
  //
  //   if (existingItem == null) {
  //     await _database
  //         .into(_database.inventoryItems)
  //         .insert(
  //           db.InventoryItemsCompanion(
  //             uuid: Value(serverItem.uuid),
  //             name: Value(serverItem.name),
  //             quantity: Value(serverItem.quantity),
  //             price: Value(double.parse(serverItem.price)),
  //             updatedAt: Value(serverUpdatedAt),
  //             isDeleted: const Value(false),
  //             isSynced: const Value(true),
  //             serverId: Value(serverItem.inventoryId.toString()),
  //           ),
  //         );
  //     return SyncResult.inserted;
  //   }
  //
  //   final localUpdatedAt = existingItem.updatedAt.toUtc();
  //   if (serverUpdatedAt.isAfter(localUpdatedAt)) {
  //     await (_database.update(
  //       _database.inventoryItems,
  //     )..where((tbl) => tbl.uuid.equals(serverItem.uuid))).write(
  //       db.InventoryItemsCompanion(
  //         name: Value(serverItem.name),
  //         quantity: Value(serverItem.quantity),
  //         price: Value(double.parse(serverItem.price)),
  //         updatedAt: Value(serverUpdatedAt),
  //         isDeleted: Value(serverItem.isDeleted),
  //         isSynced: const Value(true),
  //         serverId: Value(serverItem.inventoryId.toString()),
  //       ),
  //     );
  //     return SyncResult.updated;
  //   }
  //
  //   return SyncResult.skipped;
  // }

  // 🔹 Generic pull changes for any table
  Future<void> pullChangesGeneric<T>({
    required String tablePath,
    required T Function(Map<String, dynamic>) itemFromJson,
    required Future<SyncResult> Function(T) processItem,
  }) async {
    try {
      final apiResponse = await api.fetchServerChangesGeneric<T>(
        tablePath: tablePath,
        since: '2025-09-02T18:00:00.000Z',
        itemFromJson: itemFromJson,
      );

      if (apiResponse.status != 200 || apiResponse.data?.isEmpty != false)
        return;

      var hasChanges = false;
      for (final serverItem in apiResponse.data!) {
        try {
          final result = await processItem(serverItem);
          if (result == SyncResult.inserted || result == SyncResult.updated) {
            hasChanges = true;
          }
        } catch (_) {}
      }

      if (hasChanges) _onDataChanged?.call();
    } catch (_) {}
  }

  // 🔹 Pull changes for inventory items - backward compatibility
  Future<void> pullChanges() async {
    return pullChangesGeneric<InventoryResponse>(
      tablePath: 'inventory',
      itemFromJson: (json) => InventoryResponse.fromJson(json),
      processItem: _processServerItem,
    );
  }

  // 🔹 Generic process server item for any table
  Future<SyncResult> _processServerItemGeneric<T>({
    required T serverItem,
    required String uuid,
    required String name,
    required DateTime updatedAt,
    required bool isDeleted,
    required String serverId,
    required TableInfo table,
    required dynamic Function({
      required String uuid,
      required String name,
      required DateTime updatedAt,
      required bool isDeleted,
      required String serverId,
    })
    createCompanion,
  }) async {
    final serverUpdatedAt = _parseServerDate(updatedAt);

    final existingItem = await (_database.select(
      table,
    )..where((tbl) => (tbl as dynamic).uuid.equals(uuid))).getSingleOrNull();

    // Handle deleted items
    if (isDeleted) {
      if (existingItem != null) {
        await (_database.delete(
          table,
        )..where((tbl) => (tbl as dynamic).uuid.equals(uuid))).go();
        return SyncResult.updated;
      }
      return SyncResult.skipped;
    }

    // Handle new items
    if (existingItem == null) {
      await _database
          .into(table)
          .insert(
            createCompanion(
              uuid: uuid,
              name: name,
              updatedAt: serverUpdatedAt,
              isDeleted: false,
              serverId: serverId,
            ),
          );
      return SyncResult.inserted;
    }

    // Handle updates
    if (serverUpdatedAt.isAfter((existingItem as dynamic).updatedAt.toUtc())) {
      await (_database.update(
        table,
      )..where((tbl) => (tbl as dynamic).uuid.equals(uuid))).write(
        createCompanion(
          uuid: uuid,
          name: name,
          updatedAt: serverUpdatedAt,
          isDeleted: isDeleted,
          serverId: serverId,
        ),
      );
      return SyncResult.updated;
    }

    return SyncResult.skipped;
  }

  // 🔹 Process inventory item - backward compatibility
  Future<SyncResult> _processServerItem(InventoryResponse serverItem) async {
    return _processServerItemGeneric<InventoryResponse>(
      serverItem: serverItem,
      uuid: serverItem.uuid,
      name: serverItem.name,
      updatedAt: serverItem.updatedAt,
      isDeleted: serverItem.isDeleted,
      serverId: serverItem.inventoryId.toString(),
      table: _database.inventoryItems,
      createCompanion:
          ({
            required String uuid,
            required String name,
            required DateTime updatedAt,
            required bool isDeleted,
            required String serverId,
          }) {
            return db.InventoryItemsCompanion(
              uuid: Value(uuid),
              name: Value(name),
              quantity: Value(serverItem.quantity),
              price: Value(double.parse(serverItem.price)),
              updatedAt: Value(updatedAt),
              isDeleted: Value(isDeleted),
              isSynced: const Value(true),
              serverId: Value(serverId),
            );
          },
    );
  }

  // 🔹 Process category item - using CategoryResponse model
  Future<SyncResult> _processCategoryItem(CategoryResponse serverItem) async {
    debugPrint('🔄 Processing category item: ${serverItem.name}');
    final result = await _processServerItemGeneric<CategoryResponse>(
      serverItem: serverItem,
      uuid: serverItem.uuid,
      name: serverItem.name,
      updatedAt: serverItem.updatedAt,
      isDeleted: serverItem.isDeleted,
      serverId: serverItem.categoryId.toString(),
      table: _database.categories,
      createCompanion:
          ({
            required String uuid,
            required String name,
            required DateTime updatedAt,
            required bool isDeleted,
            required String serverId,
          }) {
            return db.CategoriesCompanion(
              uuid: Value(uuid),
              name: Value(name),
              updatedAt: Value(updatedAt),
              isDeleted: Value(isDeleted),
              isSynced: const Value(true),
              serverId: Value(serverId),
            );
          },
    );
    debugPrint('🔄 Category item processed: ${serverItem.name} - $result');
    return result;
  }

  // 🔹 Pull changes for categories - using CategoryResponse model
  Future<void> pullChangesCategories() async {
    try {
      debugPrint('🔄 Starting category pull changes...');
      final result = await pullChangesGeneric<CategoryResponse>(
        tablePath: 'categories',
        itemFromJson: (json) => CategoryResponse.fromJson(json),
        processItem: _processCategoryItem,
      );
      debugPrint('🔄 Category pull changes completed');
    } catch (e) {
      debugPrint('❌ Category pull changes failed: $e');
    }
  }
}
