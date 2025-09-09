import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../database/database.dart';
import '../widgets/inventory_item_card.dart';
import '../widgets/add_item_dialog.dart';
import 'db_view_screen.dart';
import 'category_screen.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Open Categories page
          IconButton(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const CategoryScreen()));
            },
            tooltip: 'Categories',
            icon: const Icon(Icons.category),
          ),
          Consumer<InventoryProvider>(
            builder: (context, inventoryProvider, child) {
              return IconButton(
                onPressed: () async {
                  try {
                    // Manual sync trigger with UI refresh
                    await inventoryProvider.manualSync();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sync completed!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Sync failed: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.sync),
                tooltip: 'Manual Sync',
              );
            },
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const DbViewScreen()),
              );
            },
            icon: const Icon(Icons.table_chart),
            tooltip: 'Database View',
          ),
          Consumer<AppDatabase>(
            builder: (context, database, child) {
              return IconButton(
                onPressed: () => _showClearDatabaseDialog(context, database),
                icon: const Icon(Icons.delete_forever),
                tooltip: 'Clear Database',
                style: IconButton.styleFrom(foregroundColor: Colors.red),
              );
            },
          ),
        ],
      ),
      body: Consumer<InventoryProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final activeItems = provider.items
              .where((item) => !item.isDeleted)
              .toList();

          if (activeItems.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No items in inventory',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap the + button to add your first item',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: activeItems.length,
            itemBuilder: (context, index) {
              final item = activeItems[index];
              return InventoryItemCard(
                item: item,
                onEdit: () => _showEditDialog(context, item),
                onDelete: () => _showDeleteDialog(context, item),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        tooltip: 'Add Item',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => const AddItemDialog());
  }

  void _showEditDialog(BuildContext context, InventoryItem item) {
    showDialog(
      context: context,
      builder: (context) => AddItemDialog(item: item, isEditing: true),
    );
  }

  void _showDeleteDialog(BuildContext context, InventoryItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<InventoryProvider>().deleteItem(item.uuid);
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showClearDatabaseDialog(BuildContext context, AppDatabase database) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Clear Database'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to clear all data?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('This will permanently delete:'),
            SizedBox(height: 4),
            Text('• All inventory items'),
            Text('• All sync data'),
            Text('• All local changes'),
            SizedBox(height: 8),
            Text(
              'This action cannot be undone!',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _clearDatabase(context, database);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear Database'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearDatabase(
    BuildContext context,
    AppDatabase database,
  ) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Clearing database...'),
            ],
          ),
        ),
      );

      // Clear the database
      await database.resetDatabase();

      // Reload the inventory provider
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        context.read<InventoryProvider>().loadItems();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Database cleared successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear database: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }
}
