import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/database.dart';
import 'api_service.dart';
import '../utils/network_checker.dart';
import '../models/inventory_response.dart';
import 'package:drift/drift.dart';

/// Result of processing a server item during sync
enum SyncResult {
  inserted, // New item was inserted
  updated, // Existing item was updated
  skipped, // No changes needed
}

class SyncService {
  final AppDatabase db;
  final ApiService api;
  Timer? _timer;
  VoidCallback? _onDataChanged;

  SyncService({required this.db, required this.api});

  void setOnDataChangedCallback(VoidCallback callback) {
    _onDataChanged = callback;
  }

  void startSync({Duration interval = const Duration(seconds: 10)}) {
    _timer = Timer.periodic(interval, (_) {
      batchSyncItems();
      pullChanges();
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


  Future<void> batchSyncItems() async {
    final connected = await NetworkChecker.isConnected;
    if (!connected) return;

    // get unsynced items
    final unsyncedItems = await (db.select(db.inventoryItems)
      ..where((tbl) => tbl.isSynced.equals(false)))
        .get();

    if (unsyncedItems.isEmpty) return;

    // build payload
    final payload = unsyncedItems.map((item) {
      return {
        'uuid': item.uuid,
        'name': item.name,
        'quantity': item.quantity,
        'price': item.price.toString(),
        'updatedAt': item.updatedAt.toUtc().toIso8601String(),
        'isDeleted': item.isDeleted,
      };
    }).toList();

    try {
      final apiResponse = await api.batchSyncInventory(payload);

      if (apiResponse.status == 201 && apiResponse.data != null) {
        final serverItems = apiResponse.data!;

        // Use the closure-style batch. Drift will run these queued statements
        // atomically (inside a transaction) when the callback completes.
        await db.batch((batch) {
          for (final serverItem in serverItems) {
            // Defensive: ensure serverItem has a uuid (adjust field names if needed)
            batch.update(
              db.inventoryItems,
              InventoryItemsCompanion(
                isSynced: const Value(true),
                serverId: Value(serverItem.inventoryId.toString()),
              ),
              where: (tbl) => tbl.uuid.equals(serverItem.uuid),
            );
          }
        });

        // If we reach here, the batch/transaction committed successfully.
      } else {
        debugPrint(
          'Batch sync failed: ${apiResponse.error ?? apiResponse.message}',
        );
      }
    } catch (e, st) {
      debugPrint('❌ Batch sync failed: $e\n$st');
      rethrow;
    }
  }

  /// Process a single server item with comprehensive conflict resolution
  Future<void> pullChanges() async {
    try {
      final apiResponse = await api.fetchServerChanges('2025-09-02T18:00:00.000Z');
      if (apiResponse.status != 200 || apiResponse.data?.isEmpty != false) return;

      bool hasChanges = false;
      for (final serverItem in apiResponse.data!) {
        try {
          final result = await _processServerItem(serverItem);
          hasChanges = hasChanges || result == SyncResult.inserted || result == SyncResult.updated;
        } catch (_) {}
      }

      if (hasChanges) _onDataChanged?.call();
    } catch (_) {}
  }

  Future<SyncResult> _processServerItem(InventoryResponse serverItem) async {
    final serverUpdatedAt = _parseServerDate(serverItem.updatedAt).toUtc();
    final existingItem = await (db.select(db.inventoryItems)..where((tbl) => tbl.uuid.equals(serverItem.uuid))).getSingleOrNull();

    if (serverItem.isDeleted) {
      if (existingItem != null) await (db.delete(db.inventoryItems)..where((tbl) => tbl.uuid.equals(serverItem.uuid))).go();
      return existingItem != null ? SyncResult.updated : SyncResult.skipped;
    }

    if (existingItem == null) {
      await db.into(db.inventoryItems).insert(InventoryItemsCompanion(
        uuid: Value(serverItem.uuid),
        name: Value(serverItem.name),
        quantity: Value(serverItem.quantity),
        price: Value(double.parse(serverItem.price)),
        updatedAt: Value(serverUpdatedAt),
        isDeleted: const Value(false),
        isSynced: const Value(true),
        serverId: Value(serverItem.inventoryId.toString()),
      ));
      return SyncResult.inserted;
    }

    final localUpdatedAt = existingItem.updatedAt.toUtc();
    if (serverUpdatedAt.isAfter(localUpdatedAt)) {
      await (db.update(db.inventoryItems)..where((tbl) => tbl.uuid.equals(serverItem.uuid))).write(InventoryItemsCompanion(
        name: Value(serverItem.name),
        quantity: Value(serverItem.quantity),
        price: Value(double.parse(serverItem.price)),
        updatedAt: Value(serverUpdatedAt),
        isDeleted: Value(serverItem.isDeleted),
        isSynced: const Value(true),
        serverId: Value(serverItem.inventoryId?.toString()),
      ));
      return SyncResult.updated;
    }

    return SyncResult.skipped;
  }
}
