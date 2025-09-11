import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/database.dart' as db;
import 'api_service.dart';
import '../utils/network_checker.dart';
import '../models/inventory_response.dart';
import '../models/category_response.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // 🔒 Simple safety mechanisms
  late SharedPreferences _prefs;
  final Map<String, DateTime> _lastSync = {};
  final Map<String, List<Map<String, dynamic>>> _failedItems = {};

  SyncService({required db.AppDatabase database, required this.api})
    : _database = database {
    _initializeTableConfigs();
    _initSafety();
  }

  Future<void> _initSafety() async {
    _prefs = await SharedPreferences.getInstance();
    // Load last sync times
    for (final config in _tableConfigs) {
      final saved = _prefs.getString('lastSync_${config.tablePath}');
      _lastSync[config.tablePath] = saved != null
          ? DateTime.parse(saved)
          : DateTime(2025, 9, 2, 18, 0, 0);
    }
    // Load failed items for retry
    await _loadFailedItems();
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
    _timer = Timer.periodic(interval, (_) async {
      for (final config in _tableConfigs) {
        await _batchSyncTable(config);
        await _pullChangesTable(config);
      }
      await _saveSyncTimes();
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

      // First, retry any previously failed items
      await _retryFailedItems(config);

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

      try {
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
        _onDataChanged?.call();
        // Clear failed items on success
        _failedItems[config.tablePath]?.clear();
        await _saveFailedItems();
      } catch (e) {
        // Queue failed items for retry
        _failedItems[config.tablePath] = items;
        await _saveFailedItems();
        debugPrint('❌ Batch sync failed for ${config.tablePath}: $e');
        rethrow;
      }
    } catch (e) {
      debugPrint('❌ Batch sync failed for ${config.tablePath}: $e');
    }
  }

  // 🔹 ULTRA-SIMPLE: Generic pull changes for any table
  Future<void> _pullChangesTable(TableConfig config) async {
    try {
      final lastSync =
          _lastSync[config.tablePath] ?? DateTime(2025, 9, 2, 18, 0, 0);
      final apiResponse = await api.fetchServerChangesGeneric(
        tablePath: config.tablePath,
        since: lastSync.toIso8601String(),
        itemFromJson: config.fromJson,
      );

      if (apiResponse.status != 200 || apiResponse.data?.isEmpty != false) {
        return;
      }

      // Process all items in a single batch transaction for safety
      bool hasChanges = false;
      await _database.batch((batch) async {
        for (final serverItem in apiResponse.data!) {
          try {
            final result = await _processServerItemInBatch(
              config,
              serverItem,
              batch,
            );
            if (result == SyncResult.inserted || result == SyncResult.updated) {
              hasChanges = true;
            }
          } catch (e) {
            debugPrint('❌ Error processing ${config.tablePath} item: $e');
          }
        }
      });

      if (hasChanges) {
        _lastSync[config.tablePath] = DateTime.now().toUtc();
        _onDataChanged?.call();
      }
    } catch (e) {
      debugPrint('❌ Pull changes failed for ${config.tablePath}: $e');
    }
  }

  // 🔹 ULTRA-SIMPLE: Generic process server item WITH BATCH TRANSACTION
  Future<SyncResult> _processServerItemInBatch(
    TableConfig config,
    dynamic serverItem,
    Batch batch,
  ) async {
    final uuid = config.getUuid(serverItem);
    final isDeleted = config.getIsDeleted(serverItem);

    final existingItem = await (_database.select(
      config.table,
    )..where((tbl) => (tbl as dynamic).uuid.equals(uuid))).getSingleOrNull();

    if (isDeleted) {
      if (existingItem != null) {
        batch.deleteWhere(
          config.table,
          (tbl) => (tbl as dynamic).uuid.equals(uuid),
        );
        return SyncResult.updated;
      }
      return SyncResult.skipped;
    }

    if (existingItem == null) {
      batch.insert(config.table, config.createCompanion(serverItem));
      return SyncResult.inserted;
    }

    final updatedAt = _parseServerDate(config.getUpdatedAt(serverItem));
    if (updatedAt.isAfter((existingItem as dynamic).updatedAt.toUtc())) {
      batch.update(
        config.table,
        config.createCompanion(serverItem),
        where: (tbl) => (tbl as dynamic).uuid.equals(uuid),
      );
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

  // 🔒 Save sync times to persistent storage
  Future<void> _saveSyncTimes() async {
    try {
      for (final entry in _lastSync.entries) {
        await _prefs.setString(
          'lastSync_${entry.key}',
          entry.value.toIso8601String(),
        );
      }
    } catch (e) {
      debugPrint('❌ Error saving sync times: $e');
    }
  }

  // 🔒 Load failed items from storage
  Future<void> _loadFailedItems() async {
    for (final config in _tableConfigs) {
      final key = 'failed_${config.tablePath}';
      final saved = _prefs.getStringList(key);
      if (saved != null && saved.isNotEmpty) {
        _failedItems[config.tablePath] = saved
            .map(
              (json) => Map<String, dynamic>.from(
                Uri.splitQueryString(
                  json.replaceAll('=', ':').replaceAll('&', ','),
                ),
              ),
            )
            .toList();
      }
    }
  }

  // 🔒 Save failed items to storage
  Future<void> _saveFailedItems() async {
    for (final entry in _failedItems.entries) {
      final key = 'failed_${entry.key}';
      if (entry.value.isEmpty) {
        await _prefs.remove(key);
      } else {
        final jsonList = entry.value.map((item) => item.toString()).toList();
        await _prefs.setStringList(key, jsonList);
      }
    }
  }

  // 🔒 Retry failed items for a specific table
  Future<void> _retryFailedItems(TableConfig config) async {
    final failed = _failedItems[config.tablePath];
    if (failed == null || failed.isEmpty) return;

    try {
      final resp = await api.batchSyncGeneric<Map<String, dynamic>>(
        tablePath: config.tablePath,
        items: failed,
        itemFromJson: (m) => m,
      );

      if (resp.status == 201 && resp.data != null) {
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
        // Clear failed items on success
        _failedItems[config.tablePath]?.clear();
        await _saveFailedItems();
      }
    } catch (e) {
      debugPrint('❌ Retry failed for ${config.tablePath}: $e');
    }
  }
}
