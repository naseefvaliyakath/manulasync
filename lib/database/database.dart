import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

@DriftDatabase(tables: [InventoryItems, Categories])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(categories);
      }
      if (from < 3) {
        await customStatement('DROP TABLE IF EXISTS categories');
        await m.createTable(categories);
      }
    },
  );

  /// Clear all data from both inventory and categories tables
  Future<void> clearAllData() async {
    await delete(inventoryItems).go();
    await delete(categories).go();
  }

  /// Reset the database (clear all data and reset auto-increment)
  Future<void> resetDatabase() async {
    await clearAllData();
    // Reset auto-increment counter
    await customStatement('DELETE FROM sqlite_sequence WHERE name = ?', [
      'inventory_items',
    ]);
    await customStatement('DELETE FROM sqlite_sequence WHERE name = ?', [
      'categories',
    ]);
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'inventory.db'));
    return NativeDatabase.createInBackground(file);
  });
}

class InventoryItems extends Table {
  IntColumn get localId =>
      integer().autoIncrement()(); // local-only ID (auto primary key)
  TextColumn get uuid => text()(); // unique across devices
  TextColumn get serverId => text().nullable()();

  TextColumn get name => text()();
  IntColumn get quantity => integer()();
  RealColumn get price => real()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {uuid}, // ✅ UUID must be unique across devices
  ];
}

class Categories extends Table {
  IntColumn get localId => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get serverId => text().nullable()();
  TextColumn get name => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {uuid},
  ];
}
