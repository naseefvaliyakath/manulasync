# 🔧 How to Add a New Table to Sync System

Complete step-by-step guide to add a new table with full offline-first sync capabilities.

## 📋 Quick Overview

To add a new table (e.g., "Products"), you need to:

1. ✅ **Database Table** (1 file)
2. ✅ **API Response Model** (1 file) 
3. ✅ **Sync Configuration** (1 file)
4. ✅ **Provider** (1 file)
5. ✅ **UI Screens** (2 files)
6. ✅ **Widget** (1 file)
7. ✅ **Navigation** (1 file)
8. ✅ **Code Generation**

**Total: ~8 files, ~500 lines of code**

---

## Step 1: Database Table

### 1.1 Add to `lib/database/database.dart`

```dart
// Add new table class
class Products extends Table {
  IntColumn get localId => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get serverId => text().nullable()();
  
  // Your specific fields
  TextColumn get title => text()();
  TextColumn get description => text()();
  IntColumn get stock => integer()();
  RealColumn get cost => real()();
  
  // Required sync fields (always include these)
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {uuid}, // UUID must be unique
  ];
}
```

### 1.2 Update Database Declaration

```dart
@DriftDatabase(tables: [InventoryItems, Categories, Products]) // Add Products
class AppDatabase extends _$AppDatabase {
  @override
  int get schemaVersion => 4; // Increment version

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => await m.createAll(),
    onUpgrade: (m, from, to) async {
      // ... existing migrations
      if (from < 4) {
        await m.createTable(products); // Add this
      }
    },
  );

  // Update clear methods
  Future<void> clearAllData() async {
    await delete(inventoryItems).go();
    await delete(categories).go();
    await delete(products).go(); // Add this
  }
}
```

---

## Step 2: API Response Model

### 2.1 Create `lib/models/product_response.dart`

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'product_response.freezed.dart';
part 'product_response.g.dart';

@freezed
class ProductResponse with _$ProductResponse {
  const factory ProductResponse({
    required int productId,        // Server's primary key
    required String uuid,          // Unique across devices
    required String title,         // Your fields
    required String description,
    required int stock,
    required String cost,          // Server sends as string
    required bool isDeleted,       // Required for sync
    required DateTime updatedAt,   // Required for sync
    required String serverId,      // Required for sync
  }) = _ProductResponse;

  factory ProductResponse.fromJson(Map<String, dynamic> json) =>
      _$ProductResponseFromJson(json);
}
```

### 2.2 Generate Code

```bash
flutter pub run build_runner build
```

---

## Step 3: Sync Configuration

### 3.1 Update `lib/services/sync_service.dart`

```dart
// Add import
import '../models/product_response.dart';

// In _initializeTableConfigs() method, add:
TableConfig<ProductResponse, Table, db.Product>(
  tablePath: 'products',
  table: _database.products,
  fromJson: (json) => ProductResponse.fromJson(json),
  getUuid: (item) => (item as ProductResponse).uuid,
  getUpdatedAt: (item) => (item as ProductResponse).updatedAt,
  getIsDeleted: (item) => (item as ProductResponse).isDeleted,
  getServerId: (item) => (item as ProductResponse).serverId,
  createCompanion: (item) {
    final productItem = item as ProductResponse;
    return db.ProductsCompanion(
      uuid: Value(productItem.uuid),
      title: Value(productItem.title),
      description: Value(productItem.description),
      stock: Value(productItem.stock),
      cost: Value(double.parse(productItem.cost)),
      updatedAt: Value(productItem.updatedAt),
      isDeleted: Value(productItem.isDeleted),
      isSynced: const Value(true),
      serverId: Value(productItem.serverId),
    );
  },
),
```

---

## Step 4: Provider

### 4.1 Create `lib/providers/product_provider.dart`

```dart
import 'package:flutter/material.dart';
import '../database/database.dart' as db;
import '../services/sync_service.dart';

class ProductProvider with ChangeNotifier {
  final db.AppDatabase database;
  final SyncService _syncService;
  
  List<db.Product> _products = [];
  bool _isLoading = false;

  ProductProvider(this.database, this._syncService);

  List<db.Product> get products => _products.where((p) => !p.isDeleted).toList();
  bool get isLoading => _isLoading;

  Future<void> loadProducts() async {
    _isLoading = true;
    notifyListeners();

    try {
      _products = await database.select(database.products).get();
    } catch (e) {
      debugPrint('Error loading products: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addProduct({
    required String title,
    required String description,
    required int stock,
    required double cost,
  }) async {
    try {
      await database.into(database.products).insert(
        db.ProductsCompanion(
          uuid: Value(_generateUuid()),
          title: Value(title),
          description: Value(description),
          stock: Value(stock),
          cost: Value(cost),
        ),
      );
      await loadProducts();
    } catch (e) {
      debugPrint('Error adding product: $e');
    }
  }

  Future<void> updateProduct({
    required int localId,
    required String title,
    required String description,
    required int stock,
    required double cost,
  }) async {
    try {
      await (database.update(database.products)
            ..where((tbl) => tbl.localId.equals(localId)))
          .write(db.ProductsCompanion(
            title: Value(title),
            description: Value(description),
            stock: Value(stock),
            cost: Value(cost),
            updatedAt: Value(DateTime.now().toUtc()),
          ));
      await loadProducts();
    } catch (e) {
      debugPrint('Error updating product: $e');
    }
  }

  Future<void> deleteProduct(int localId) async {
    try {
      await (database.update(database.products)
            ..where((tbl) => tbl.localId.equals(localId)))
          .write(db.ProductsCompanion(
            isDeleted: const Value(true),
            updatedAt: Value(DateTime.now().toUtc()),
          ));
      await loadProducts();
    } catch (e) {
      debugPrint('Error deleting product: $e');
    }
  }

  Future<void> manualSync() async => await loadProducts();
  Future<void> forceRefresh() async => await loadProducts();

  String _generateUuid() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
           (1000 + (DateTime.now().microsecond % 9000)).toString();
  }
}
```

---

## Step 5: UI Screens

### 5.1 Create `lib/screens/product_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/product_provider.dart';
import '../database/database.dart' as db;
import 'product_db_view_screen.dart';
import '../widgets/add_product_dialog.dart';

class ProductScreen extends StatefulWidget {
  const ProductScreen({Key? key}) : super(key: key);

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().loadProducts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            onPressed: () => context.read<ProductProvider>().manualSync(),
            icon: const Icon(Icons.sync),
            tooltip: 'Manual Sync',
          ),
          IconButton(
            onPressed: () => context.read<ProductProvider>().forceRefresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Force Refresh',
          ),
          IconButton(
            onPressed: () => _showClearDatabaseDialog(context),
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear Database',
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProductDbViewScreen()),
            ),
            icon: const Icon(Icons.storage),
            tooltip: 'DB View',
          ),
        ],
      ),
      body: Consumer<ProductProvider>(
        builder: (context, productProvider, child) {
          if (productProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final products = productProvider.products;
          if (products.isEmpty) {
            return const Center(
              child: Text(
                'No products found.\nTap + to add a product.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(product.title),
                  subtitle: Text(product.description),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Stock: ${product.stock}'),
                      Text('\$${product.cost.toStringAsFixed(2)}'),
                    ],
                  ),
                  onTap: () => _showEditProductDialog(context, product),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddProductDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddProductDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const AddProductDialog(),
    );
  }

  void _showEditProductDialog(BuildContext context, db.Product product) {
    showDialog(
      context: context,
      builder: (context) => AddProductDialog(product: product),
    );
  }

  void _showClearDatabaseDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Database'),
        content: const Text('Are you sure you want to clear all products?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<db.AppDatabase>().clearAllData();
              context.read<ProductProvider>().loadProducts();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Database cleared')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
```

### 5.2 Create `lib/screens/product_db_view_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/database.dart' as db;
import '../utils/date_utils.dart';

class ProductDbViewScreen extends StatelessWidget {
  const ProductDbViewScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products DB View'),
        backgroundColor: Colors.blue[900],
      ),
      body: StreamBuilder<List<db.Product>>(
        stream: context.read<db.AppDatabase>().select(context.read<db.AppDatabase>().products).watch(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final products = snapshot.data ?? [];
          if (products.isEmpty) {
            return const Center(child: Text('No products in database'));
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('ID', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('UUID', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Title', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Description', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Stock', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Cost', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Updated At', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Deleted', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Synced', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: products.map((product) {
                return DataRow(
                  color: MaterialStateProperty.resolveWith<Color?>(
                    (Set<MaterialState> states) {
                      if (product.isDeleted) return Colors.red[50];
                      if (!product.isSynced) return Colors.orange[50];
                      return null;
                    },
                  ),
                  cells: [
                    DataCell(Text(product.localId.toString())),
                    DataCell(Text(product.uuid, style: const TextStyle(fontFamily: 'monospace', fontSize: 10))),
                    DataCell(Text(product.title)),
                    DataCell(Text(product.description)),
                    DataCell(Text(product.stock.toString())),
                    DataCell(Text(product.cost.toStringAsFixed(2))),
                    DataCell(Text(DateUtils.formatDateTime(product.updatedAt))),
                    DataCell(Icon(
                      product.isDeleted ? Icons.check_circle : Icons.cancel,
                      color: product.isDeleted ? Colors.red : Colors.green,
                    )),
                    DataCell(Icon(
                      product.isSynced ? Icons.check_circle : Icons.sync_problem,
                      color: product.isSynced ? Colors.green : Colors.orange,
                    )),
                  ],
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}
```

---

## Step 6: Dialog Widget

### 6.1 Create `lib/widgets/add_product_dialog.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/product_provider.dart';
import '../database/database.dart' as db;

class AddProductDialog extends StatefulWidget {
  final db.Product? product;

  const AddProductDialog({Key? key, this.product}) : super(key: key);

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _stockController;
  late TextEditingController _costController;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _titleController = TextEditingController(text: product?.title ?? '');
    _descriptionController = TextEditingController(text: product?.description ?? '');
    _stockController = TextEditingController(text: product?.stock.toString() ?? '');
    _costController = TextEditingController(text: product?.cost.toString() ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _stockController.dispose();
    _costController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.product != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Product' : 'Add Product'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a description';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _stockController,
              decoration: const InputDecoration(
                labelText: 'Stock',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter stock quantity';
                }
                final stock = int.tryParse(value);
                if (stock == null || stock < 0) {
                  return 'Please enter a valid stock quantity';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _costController,
              decoration: const InputDecoration(
                labelText: 'Cost',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a cost';
                }
                final cost = double.tryParse(value);
                if (cost == null || cost < 0) {
                  return 'Please enter a valid cost';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveProduct,
          child: Text(isEditing ? 'Update' : 'Add'),
        ),
      ],
    );
  }

  void _saveProduct() {
    if (!_formKey.currentState!.validate()) return;

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final stock = int.parse(_stockController.text.trim());
    final cost = double.parse(_costController.text.trim());

    if (widget.product != null) {
      context.read<ProductProvider>().updateProduct(
        localId: widget.product!.localId,
        title: title,
        description: description,
        stock: stock,
        cost: cost,
      );
    } else {
      context.read<ProductProvider>().addProduct(
        title: title,
        description: description,
        stock: stock,
        cost: cost,
      );
    }

    Navigator.pop(context);
  }
}
```

---

## Step 7: Update Main App

### 7.1 Add Provider to `lib/main.dart`

```dart
// Add import
import 'providers/product_provider.dart';

// Add to MultiProvider
ChangeNotifierProxyProvider2<db.AppDatabase, SyncService>(
  create: (context) => ProductProvider(
    context.read<db.AppDatabase>(),
    context.read<SyncService>(),
  ),
  update: (context, database, syncService, previous) =>
      previous ?? ProductProvider(database, syncService),
),
```

### 7.2 Add Navigation

Add navigation to ProductScreen from your main app:

```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const ProductScreen()),
);
```

---

## Step 8: Final Steps

### 8.1 Generate Code

```bash
flutter pub run build_runner build
```

### 8.2 Test

```bash
flutter build apk --debug
```

---

## 🎯 What You Get

Your new table will automatically have:

- ✅ **Offline-First**: Works completely offline
- ✅ **Auto Sync**: Syncs when online (every 5 seconds)
- ✅ **Conflict Resolution**: Last-write-wins based on timestamps
- ✅ **Soft Deletes**: Items marked deleted, not removed
- ✅ **Retry Logic**: Failed syncs retry automatically
- ✅ **Crash Recovery**: Survives app crashes
- ✅ **UI Updates**: Real-time UI refresh
- ✅ **DB View**: Raw database inspection
- ✅ **Type Safety**: Full compile-time safety

## 🚀 Ready!

Your new table is now fully integrated into the offline-first sync system! 🎉
