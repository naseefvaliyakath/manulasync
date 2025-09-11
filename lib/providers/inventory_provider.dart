import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';
import '../database/database.dart';
import '../services/sync_service.dart';

class InventoryProvider with ChangeNotifier {
  final AppDatabase _database;
  List<InventoryItem> _items = [];
  bool _isLoading = false;
  final SyncService _syncService; // Add sync service

  InventoryProvider(this._database, this._syncService) {
    loadItems();
    // Set up callback to refresh UI when sync service fetches new data
    _syncService.setOnDataChangedCallback(() {
      loadItems();
    });
  }

  List<InventoryItem> get items => _items;
  bool get isLoading => _isLoading;

  Future<void> loadItems() async {
    _isLoading = true;
    notifyListeners();

    try {
      _items = await _database.select(_database.inventoryItems).get();
    } catch (e) {
      debugPrint('Error loading items: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addItem({
    required String name,
    required int quantity,
    required double price,
  }) async {
    try {
      final uuid = const Uuid().v4();
      await _database
          .into(_database.inventoryItems)
          .insert(
            InventoryItemsCompanion.insert(
              uuid: uuid,
              name: name,
              quantity: quantity,
              price: price,
              // Let DB set UTC timestamp
              updatedAt: const Value.absent(),
            ),
          );

      await loadItems();
    } catch (e) {
      debugPrint('Error adding item: $e');
    }
  }

  Future<void> updateItem({
    required int localId,
    required String name,
    required int quantity,
    required double price,
  }) async {
    try {
      await (_database.update(
        _database.inventoryItems,
      )..where((tbl) => tbl.localId.equals(localId))).write(
        InventoryItemsCompanion.custom(
          name: Constant(name),
          quantity: Constant(quantity),
          price: Constant(price),
          updatedAt: currentDateAndTime, // DB UTC now
          isSynced: const Constant(false),
        ),
      );

      await loadItems();
    } catch (e) {
      debugPrint('Error updating item: $e');
    }
  }

  Future<void> deleteItem(String uuid) async {
    try {
      await (_database.update(
        _database.inventoryItems,
      )..where((tbl) => tbl.uuid.equals(uuid))).write(
        InventoryItemsCompanion.custom(
          isDeleted: const Constant(true),
          updatedAt: currentDateAndTime, // DB UTC now
          isSynced: const Constant(false),
        ),
      );

      await loadItems();
    } catch (e) {
      debugPrint('Error deleting item: $e');
    }
  }

  // Method to manually trigger sync and refresh
  Future<void> manualSync() async {
    try {
      // The sync service handles all tables automatically
      await loadItems(); // Just refresh the UI
    } catch (e) {
      debugPrint('Error during manual sync: $e');
    }
  }
}
