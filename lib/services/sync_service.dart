import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/database.dart' as db;
import 'api_service.dart';
import '../utils/network_checker.dart';
import '../models/inventory_response.dart';
import '../models/category_response.dart';
import 'package:drift/drift.dart';

/// Table configuration for sync operations
class TableConfig<TResponse, TTable extends Table, TData extends DataClass> {
  final String tablePath;
  final TableInfo<TTable, TData> table;
  final TResponse Function(Map<String, dynamic>) fromJson;
  final String Function(dynamic) getUuid;
  final DateTime Function(dynamic) getUpdatedAt;
  final bool Function(dynamic) getIsDeleted;
  final String Function(dynamic) getServerId;
  final dynamic Function(dynamic) createCompanion;

  const TableConfig({
    required this.tablePath,
    required this.table,
    required this.fromJson,
    required this.getUuid,
    required this.getUpdatedAt,
    required this.getIsDeleted,
    required this.getServerId,
    required this.createCompanion,
  });
}

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

  // Table registry - add new tables here with minimal code
  late final List<TableConfig> _tableConfigs;

  SyncService({required db.AppDatabase database, required this.api})
    : _database = database {
    _initializeTableConfigs();
  }

  void _initializeTableConfigs() {
    _tableConfigs = [
      // Inventory table config
      TableConfig<InventoryResponse, Table, db.InventoryItem>(
        tablePath: 'inventory',
        table: _database.inventoryItems,
        fromJson: (json) => InventoryResponse.fromJson(json),
        getUuid: (item) => (item as InventoryResponse).uuid,
        getUpdatedAt: (item) => (item as InventoryResponse).updatedAt,
        getIsDeleted: (item) => (item as InventoryResponse).isDeleted,
        getServerId: (item) => (item as InventoryResponse).serverId,
        createCompanion: (item) {
          final inventoryItem = item as InventoryResponse;
          return db.InventoryItemsCompanion(
            uuid: Value(inventoryItem.uuid),
            name: Value(inventoryItem.name),
            quantity: Value(inventoryItem.quantity),
            price: Value(double.parse(inventoryItem.price)),
            updatedAt: Value(inventoryItem.updatedAt),
            isDeleted: Value(inventoryItem.isDeleted),
            isSynced: const Value(true),
            serverId: Value(inventoryItem.serverId),
          );
        },
      ),
      // Category table config
      TableConfig<CategoryResponse, Table, db.Category>(
        tablePath: 'categories',
        table: _database.categories,
        fromJson: (json) => CategoryResponse.fromJson(json),
        getUuid: (item) => (item as CategoryResponse).uuid,
        getUpdatedAt: (item) => (item as CategoryResponse).updatedAt,
        getIsDeleted: (item) => (item as CategoryResponse).isDeleted,
        getServerId: (item) => (item as CategoryResponse).serverId,
        createCompanion: (item) {
          final categoryItem = item as CategoryResponse;
          return db.CategoriesCompanion(
            uuid: Value(categoryItem.uuid),
            name: Value(categoryItem.name),
            updatedAt: Value(categoryItem.updatedAt),
            isDeleted: Value(categoryItem.isDeleted),
            isSynced: const Value(true),
            serverId: Value(categoryItem.serverId),
          );
        },
      ),
    ];
  }

  void setOnDataChangedCallback(VoidCallback callback) {
    _onDataChanged = callback;
  }

  void startSync({Duration interval = const Duration(seconds: 5)}) {
    _timer = Timer.periodic(interval, (_) {
      // Batch sync all tables
      for (final config in _tableConfigs) {
        _batchSyncTable(config);
      }
      // Pull changes for all tables
      for (final config in _tableConfigs) {
        _pullChangesTable(config);
      }
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

  // 🔹 ULTRA-SIMPLE: Generic batch sync for any table
  Future<void> _batchSyncTable(TableConfig config) async {
    try {
      final connected = await NetworkChecker.isConnected;
      if (!connected) return;

      final unsynced =
          await (_database.select(config.table)
                ..where((t) => (t as dynamic).isSynced.equals(false))
                ..limit(100))
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
        tablePath: config.tablePath,
        items: items,
        itemFromJson: (m) => m,
      );

      if (resp.status != 201 || resp.data == null) return;

      await _database.batch((batch) {
        for (final item in resp.data!) {
          final uuid = item['uuid']?.toString();
          final serverId = item['serverId']?.toString();
          if (uuid == null || serverId == null) continue;

          final companion = _createCompanionForTable(
            config.table.actualTableName,
            serverId,
          );
          if (companion != null) {
            batch.update(
              config.table,
              companion,
              where: (tbl) => (tbl as dynamic).uuid.equals(uuid),
            );
          }
        }
      });
    } catch (e) {
      debugPrint('❌ Batch sync failed for ${config.tablePath}: $e');
    }
  }

  // 🔹 ULTRA-SIMPLE: Generic pull changes for any table
  Future<void> _pullChangesTable(TableConfig config) async {
    try {
      final apiResponse = await api.fetchServerChangesGeneric(
        tablePath: config.tablePath,
        since: '2025-09-02T18:00:00.000Z',
        itemFromJson: config.fromJson,
      );

      if (apiResponse.status != 200 || apiResponse.data?.isEmpty != false)
        return;

      bool hasChanges = false;
      for (final serverItem in apiResponse.data!) {
        try {
          final result = await _processServerItem(config, serverItem);
          if (result == SyncResult.inserted || result == SyncResult.updated) {
            hasChanges = true;
          }
        } catch (e) {
          debugPrint('❌ Error processing ${config.tablePath} item: $e');
        }
      }

      if (hasChanges) _onDataChanged?.call();
    } catch (e) {
      debugPrint('❌ Pull changes failed for ${config.tablePath}: $e');
    }
  }

  // 🔹 ULTRA-SIMPLE: Generic process server item
  Future<SyncResult> _processServerItem(
    TableConfig config,
    dynamic serverItem,
  ) async {
    final uuid = config.getUuid(serverItem);
    final isDeleted = config.getIsDeleted(serverItem);

    final existingItem = await (_database.select(
      config.table,
    )..where((tbl) => (tbl as dynamic).uuid.equals(uuid))).getSingleOrNull();

    if (isDeleted) {
      if (existingItem != null) {
        await (_database.delete(
          config.table,
        )..where((tbl) => (tbl as dynamic).uuid.equals(uuid))).go();
        return SyncResult.updated;
      }
      return SyncResult.skipped;
    }

    if (existingItem == null) {
      await _database
          .into(config.table)
          .insert(config.createCompanion(serverItem));
      return SyncResult.inserted;
    }

    final updatedAt = _parseServerDate(config.getUpdatedAt(serverItem));
    if (updatedAt.isAfter((existingItem as dynamic).updatedAt.toUtc())) {
      await (_database.update(config.table)
            ..where((tbl) => (tbl as dynamic).uuid.equals(uuid)))
          .write(config.createCompanion(serverItem));
      return SyncResult.updated;
    }

    return SyncResult.skipped;
  }

  // 🔹 Helper method to create companion for any table
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
        return null;
    }
  }

  // 🔹 Backward compatibility methods (for existing code)
  Future<void> batchSyncItems() async {
    final config = _tableConfigs.firstWhere((c) => c.tablePath == 'inventory');
    await _batchSyncTable(config);
  }

  Future<void> batchSyncCategories() async {
    final config = _tableConfigs.firstWhere((c) => c.tablePath == 'categories');
    await _batchSyncTable(config);
  }

  Future<void> pullChanges() async {
    final config = _tableConfigs.firstWhere((c) => c.tablePath == 'inventory');
    await _pullChangesTable(config);
  }

  Future<void> pullChangesCategories() async {
    final config = _tableConfigs.firstWhere((c) => c.tablePath == 'categories');
    await _pullChangesTable(config);
  }
}
