import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart' as db;

class CategoryProvider with ChangeNotifier {
  final db.AppDatabase _database;
  List<db.Category> _categories = [];
  bool _isLoading = false;

  CategoryProvider(this._database) {
    loadCategories();
  }

  List<db.Category> get categories => _categories;
  bool get isLoading => _isLoading;

  Future<void> loadCategories() async {
    _isLoading = true;
    notifyListeners();
    try {
      // Only load non-deleted categories
      _categories = await (_database.select(
        _database.categories,
      )..where((tbl) => tbl.isDeleted.equals(false))).get();
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
          .insert(db.CategoriesCompanion.insert(uuid: uuid, name: name));
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
          updatedAt: currentDateAndTime,
          isSynced: const Constant(false),
        ),
      );
      await loadCategories();
    } catch (e) {
      debugPrint('Error updating category: $e');
    }
  }

  Future<void> deleteCategory(int localId) async {
    try {
      await (_database.update(
        _database.categories,
      )..where((tbl) => tbl.localId.equals(localId))).write(
        db.CategoriesCompanion.custom(
          isDeleted: const Constant(true),
          updatedAt: currentDateAndTime,
          isSynced: const Constant(false),
        ),
      );
      await loadCategories();
    } catch (e) {
      debugPrint('Error deleting category: $e');
    }
  }
}
