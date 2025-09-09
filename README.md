# Inventory Management App

A simple offline CRUD inventory management app built with Flutter.

## Features

- **Add Items**: Add new inventory items with name, quantity, and price
- **View Items**: Display all inventory items in a clean list format
- **Edit Items**: Update existing inventory items
- **Delete Items**: Remove items from inventory (soft delete)
- **Offline First**: All data is stored locally using SQLite
- **State Management**: Uses Provider for clean state management

## Database Schema

The app uses a single `InventoryItems` table with the following fields:

- `localId`: Auto-incrementing local ID
- `uuid`: Unique identifier across devices
- `serverId`: Optional server ID for future sync
- `name`: Item name
- `quantity`: Item quantity
- `price`: Item price
- `updatedAt`: Last update timestamp
- `isDeleted`: Soft delete flag
- `isSynced`: Sync status flag

## Tech Stack

- **Flutter**: UI framework
- **Drift**: SQLite database ORM
- **Provider**: State management
- **UUID**: Unique identifier generation

## Getting Started

1. Clone the repository
2. Run `flutter pub get` to install dependencies
3. Run `flutter packages pub run build_runner build` to generate database code
4. Run `flutter run` to start the app

## Usage

1. Tap the "+" button to add a new inventory item
2. Fill in the item details (name, quantity, price)
3. Tap "Add" to save the item
4. Use the menu (three dots) on each item to edit or delete
5. All changes are saved locally and persist between app sessions
