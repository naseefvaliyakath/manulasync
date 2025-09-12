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
  final dynamic Function(String serverId) createSyncCompanion;

  const TableConfig({
    required this.tablePath,
    required this.table,
    required this.fromJson,
    required this.getUuid,
    required this.getUpdatedAt,
    required this.getIsDeleted,
    required this.getServerId,
    required this.createCompanion,
    required this.createSyncCompanion,
  });
}

/// Result of processing a server item during sync
enum SyncResult { inserted, updated, skipped }

class SyncService {
  final db.AppDatabase _database;
  final ApiService api;
  Timer? _timer;
  VoidCallback? _onDataChanged;

  late final List<TableConfig> _tableConfigs;

  // Safety mechanisms
  late SharedPreferences _prefs;
  final Map<String, DateTime> _lastSync = {};
  final Map<String, List<Map<String, dynamic>>> _failedItems = {};

  // Retry configuration
  static const int _maxRetryAttempts = 3;
  final Map<String, Map<String, int>> _retryCounts = {};

  SyncService({required db.AppDatabase database, required this.api})
    : _database = database {
    _initializeTableConfigs();
    _initSafety();
  }

  Future<void> _initSafety() async {
    _prefs = await SharedPreferences.getInstance();
    for (final config in _tableConfigs) {
      final saved = _prefs.getString('lastSync_${config.tablePath}');
      _lastSync[config.tablePath] = saved != null
          ? DateTime.parse(saved)
          : DateTime(2025, 9, 2, 18, 0, 0);
    }
    await _loadFailedItems();
    await _loadRetryCounts();
  }

  void _initializeTableConfigs() {
    _tableConfigs = [
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
            lastSyncedAt: Value(DateTime.now().toUtc()),
            isDeleted: Value(inventoryItem.isDeleted),
            isSynced: const Value(true),
            serverId: Value(inventoryItem.serverId),
          );
        },
        createSyncCompanion: (serverId) => db.InventoryItemsCompanion(
          isSynced: const Value(true),
          serverId: Value(serverId),
          lastSyncedAt: Value(DateTime.now().toUtc()),
        ),
      ),
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
            lastSyncedAt: Value(DateTime.now().toUtc()),
            isDeleted: Value(categoryItem.isDeleted),
            isSynced: const Value(true),
            serverId: Value(categoryItem.serverId),
          );
        },
        createSyncCompanion: (serverId) => db.CategoriesCompanion(
          isSynced: const Value(true),
          serverId: Value(serverId),
          lastSyncedAt: Value(DateTime.now().toUtc()),
        ),
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

  Future<void> _batchSyncTable(TableConfig config) async {
    try {
      final connected = await NetworkChecker.isConnected;

      if (connected) {
        await _retryFailedItems(config);
      }

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
          ..remove('lastSyncedAt')
          ..update(
            'updatedAt',
            (v) => v is DateTime ? v.toUtc().toIso8601String() : v,
          );
      }).toList();

      if (items.isEmpty) return;

      if (!connected) {
        _failedItems[config.tablePath] = items;
        for (final item in items) {
          final uuid = item['uuid']?.toString();
          if (uuid != null) {
            _incrementRetryCount(config.tablePath, uuid);
          }
        }
        await _saveFailedItems();
        await _saveRetryCounts();
        return;
      }

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
        _failedItems[config.tablePath]?.clear();
        await _saveFailedItems();
      } catch (e) {
        _failedItems[config.tablePath] = items;
        for (final item in items) {
          final uuid = item['uuid']?.toString();
          if (uuid != null) {
            _incrementRetryCount(config.tablePath, uuid);
          }
        }
        await _saveFailedItems();
        await _saveRetryCounts();
      }
    } catch (e) {
      // Silent error handling
    }
  }

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

      bool hasChanges = false;
      final itemsToProcess = <Map<String, dynamic>>[];

      for (final serverItem in apiResponse.data!) {
        try {
          final uuid = config.getUuid(serverItem);
          final isDeleted = config.getIsDeleted(serverItem);

          final existingItem =
              await (_database.select(config.table)
                    ..where((tbl) => (tbl as dynamic).uuid.equals(uuid)))
                  .getSingleOrNull();

          itemsToProcess.add({
            'serverItem': serverItem,
            'uuid': uuid,
            'isDeleted': isDeleted,
            'existingItem': existingItem,
          });
        } catch (e) {
          // Silent error handling
        }
      }

      await _database.batch((batch) {
        for (final item in itemsToProcess) {
          try {
            final result = _processServerItemInBatchSync(
              config,
              item['serverItem'],
              item['uuid'],
              item['isDeleted'],
              item['existingItem'],
              batch,
            );
            if (result == SyncResult.inserted || result == SyncResult.updated) {
              hasChanges = true;
            }
          } catch (e) {
            // Silent error handling
          }
        }
      });

      if (hasChanges) {
        _lastSync[config.tablePath] = DateTime.now().toUtc();
        _onDataChanged?.call();
      }
    } catch (e) {
      // Silent error handling
    }
  }

  SyncResult _processServerItemInBatchSync(
    TableConfig config,
    dynamic serverItem,
    String uuid,
    bool isDeleted,
    dynamic existingItem,
    Batch batch,
  ) {
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

  dynamic _createCompanionForTable(String tableName, String serverId) {
    for (final config in _tableConfigs) {
      if (config.table.actualTableName == tableName ||
          config.tablePath == tableName) {
        try {
          return config.createSyncCompanion(serverId);
        } catch (e) {
          return null;
        }
      }
    }
    return null;
  }

  Future<void> _saveSyncTimes() async {
    try {
      for (final entry in _lastSync.entries) {
        await _prefs.setString(
          'lastSync_${entry.key}',
          entry.value.toIso8601String(),
        );
      }
    } catch (e) {
      // Silent error handling
    }
  }

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

  Future<void> _retryFailedItems(TableConfig config) async {
    final failed = _failedItems[config.tablePath];
    if (failed == null || failed.isEmpty) return;

    final itemsToRetry = <Map<String, dynamic>>[];
    final itemsToRemove = <Map<String, dynamic>>[];

    for (final item in failed) {
      final uuid = item['uuid']?.toString();
      if (uuid == null) continue;

      final retryCount = _getRetryCount(config.tablePath, uuid);

      if (retryCount < _maxRetryAttempts) {
        itemsToRetry.add(item);
      } else {
        itemsToRemove.add(item);
      }
    }

    for (final item in itemsToRemove) {
      _failedItems[config.tablePath]?.remove(item);
      _removeRetryCount(config.tablePath, item['uuid']?.toString());
    }

    if (itemsToRetry.isEmpty) {
      await _saveFailedItems();
      await _saveRetryCounts();
      return;
    }

    try {
      final resp = await api.batchSyncGeneric<Map<String, dynamic>>(
        tablePath: config.tablePath,
        items: itemsToRetry,
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
              _removeRetryCount(config.tablePath, uuid);
            }
          }
        });

        final successfulUuids = resp.data!
            .map((item) => item['uuid']?.toString())
            .where((uuid) => uuid != null)
            .toSet();
        _failedItems[config.tablePath]?.removeWhere(
          (item) => successfulUuids.contains(item['uuid']?.toString()),
        );

        await _saveFailedItems();
        await _saveRetryCounts();
      } else {
        for (final item in itemsToRetry) {
          final uuid = item['uuid']?.toString();
          if (uuid != null) {
            _incrementRetryCount(config.tablePath, uuid);
          }
        }
        await _saveRetryCounts();
      }
    } catch (e) {
      for (final item in itemsToRetry) {
        final uuid = item['uuid']?.toString();
        if (uuid != null) {
          _incrementRetryCount(config.tablePath, uuid);
        }
      }
      await _saveRetryCounts();
    }
  }

  int _getRetryCount(String tablePath, String uuid) {
    return _retryCounts[tablePath]?[uuid] ?? 0;
  }

  void _incrementRetryCount(String tablePath, String uuid) {
    _retryCounts[tablePath] ??= {};
    _retryCounts[tablePath]![uuid] = (_retryCounts[tablePath]![uuid] ?? 0) + 1;
  }

  void _removeRetryCount(String tablePath, String? uuid) {
    if (uuid != null) {
      _retryCounts[tablePath]?.remove(uuid);
    }
  }

  Future<void> _loadRetryCounts() async {
    try {
      for (final config in _tableConfigs) {
        final retryData = _prefs.getString('retryCounts_${config.tablePath}');
        if (retryData != null) {
          final Map<String, dynamic> parsed = Map<String, dynamic>.from(
            Uri.splitQueryString(retryData),
          );
          _retryCounts[config.tablePath] = parsed.map(
            (key, value) => MapEntry(key, int.tryParse(value) ?? 0),
          );
        }
      }
    } catch (e) {
      // Silent error handling
    }
  }

  Future<void> _saveRetryCounts() async {
    try {
      for (final config in _tableConfigs) {
        final retryData = _retryCounts[config.tablePath];
        if (retryData != null && retryData.isNotEmpty) {
          final queryString = retryData.entries
              .map((e) => '${Uri.encodeComponent(e.key)}=${e.value}')
              .join('&');
          await _prefs.setString(
            'retryCounts_${config.tablePath}',
            queryString,
          );
        } else {
          await _prefs.remove('retryCounts_${config.tablePath}');
        }
      }
    } catch (e) {
      // Silent error handling
    }
  }
}
