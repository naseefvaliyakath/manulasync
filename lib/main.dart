import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'database/database.dart';
import 'providers/inventory_provider.dart';
import 'providers/category_provider.dart';
import 'screens/inventory_screen.dart';
import 'services/api_service.dart';
import 'services/sync_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // print(DateTime.now().toUtc().toIso8601String());
    return MultiProvider(
      providers: [
        // Drift database
        Provider<AppDatabase>(
          create: (_) => AppDatabase(),
          dispose: (_, db) => db.close(),
        ),

        // API Service
        Provider<ApiService>(
          create: (_) =>
              ApiService(baseUrl: 'https://mobizate.com/offlineSync'),
        ),

        // Sync Service
        ProxyProvider2<AppDatabase, ApiService, SyncService>(
          create: (context) {
            final syncService = SyncService(
              database: context.read<AppDatabase>(),
              api: context.read<ApiService>(),
            );
            syncService.startSync(
              interval: const Duration(seconds: 10),
            ); // auto-sync every 10s
            return syncService;
          },
          update: (_, db, api, previous) =>
              previous ?? SyncService(database: db, api: api),
          dispose: (_, sync) => sync.stopSync(),
        ),

        // Inventory Provider
        ChangeNotifierProxyProvider2<
          AppDatabase,
          SyncService,
          InventoryProvider
        >(
          create: (context) => InventoryProvider(
            context.read<AppDatabase>(),
            context.read<SyncService>(),
          ),
          update: (context, db, sync, previous) =>
              previous ?? InventoryProvider(db, sync),
        ),

        // Category Provider
        ChangeNotifierProxyProvider2<
          AppDatabase,
          SyncService,
          CategoryProvider
        >(
          create: (context) => CategoryProvider(
            context.read<AppDatabase>(),
            context.read<SyncService>(),
          ),
          update: (context, db, sync, previous) =>
              previous ?? CategoryProvider(db, sync),
        ),
      ],
      child: MaterialApp(
        title: 'Inventory Management',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const InventoryScreen(),
      ),
    );
  }
}
