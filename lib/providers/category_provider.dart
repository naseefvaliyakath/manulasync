import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart' as db;
import '../services/sync_service.dart';

class CategoryProvider with ChangeNotifier {
  final db.AppDatabase _database;
  List<db.Category> _categories = [];
  bool _isLoading = false;
  final SyncService _syncService; // Add sync service

  CategoryProvider(this._database, this._syncService) {
    loadCategories();
    // Set up callback to refresh UI when sync service fetches new data
    _syncService.setOnDataChangedCallback(() {
      loadCategories();
    });
  }

  List<db.Category> get categories => _categories;
  bool get isLoading => _isLoading;

  Future<void> loadCategories() async {
    _isLoading = true;
    notifyListeners();

    try {
      _categories = await _database.select(_database.categories).get();
    } catch (e) {
      debugPrint('Error loading categories: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addCategory({required String name}) async {
    try {
      final uuid = const Uuid().v4();
      await _database
          .into(_database.categories)
          .insert(
            db.CategoriesCompanion.insert(
              uuid: uuid,
              name: name,
              // Let DB set UTC timestamp
              updatedAt: const Value.absent(),
            ),
          );

      await loadCategories();
    } catch (e) {
      debugPrint('Error adding category: $e');
    }
  }

  Future<void> updateCategory({
    required int localId,
    required String name,
  }) async {
    try {
      await (_database.update(
        _database.categories,
      )..where((tbl) => tbl.localId.equals(localId))).write(
        db.CategoriesCompanion.custom(
          name: Constant(name),
          updatedAt: currentDateAndTime, // DB UTC now
          isSynced: const Constant(false),
        ),
      );

      await loadCategories();
    } catch (e) {
      debugPrint('Error updating category: $e');
    }
  }

  Future<void> deleteCategory(String uuid) async {
    try {
      await (_database.update(
        _database.categories,
      )..where((tbl) => tbl.uuid.equals(uuid))).write(
        db.CategoriesCompanion.custom(
          isDeleted: const Constant(true),
          updatedAt: currentDateAndTime, // DB UTC now
          isSynced: const Constant(false),
        ),
      );

      await loadCategories();
    } catch (e) {
      debugPrint('Error deleting category: $e');
    }
  }

  // Method to manually trigger sync and refresh
  Future<void> manualSync() async {
    try {
      // The sync service handles all tables automatically
      await loadCategories(); // Just refresh the UI
    } catch (e) {
      debugPrint('Error during manual sync: $e');
    }
  }

  // Method to force refresh UI - useful for debugging
  Future<void> forceRefresh() async {
    await loadCategories();
  }
}
