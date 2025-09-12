# 🧪 **HOW TO TEST RETRY LIMITS - COMPREHENSIVE TESTING GUIDE**

## ✅ **Debug Logs Added for Testing**

I've added comprehensive debug logging to verify the retry limit functionality is working correctly. Here's how to test it:

---

## 🔍 **Debug Logs You'll See:**

### **1. Initial Sync Failure:**
```
❌ Batch sync failed for inventory: Network error
🔄 Queuing 2 items for retry
🔄 Item abc-123: retry count incremented (0 → 1) - initial sync failure
🔄 Item def-456: retry count incremented (0 → 1) - initial sync failure
```

### **2. Retry Process:**
```
🔄 Starting retry for inventory: 2 failed items
🔄 Item abc-123: retry count = 1/3
✅ Item abc-123: will retry (attempt 2/3)
🔄 Item def-456: retry count = 1/3
✅ Item def-456: will retry (attempt 2/3)
🔄 Retry summary: 2 items to retry, 0 items exceeded limit
🔄 Attempting to sync 2 items for inventory
```

### **3. Retry Success:**
```
✅ Retry sync successful for inventory: 2 items synced
✅ Item abc-123: retry count cleared (sync successful)
✅ Item def-456: retry count cleared (sync successful)
```

### **4. Retry Failure:**
```
❌ Retry sync failed for inventory: status 500
🔄 Item abc-123: retry count incremented (1 → 2)
🔄 Item def-456: retry count incremented (1 → 2)
```

### **5. Exceeding Retry Limit:**
```
🔄 Starting retry for inventory: 1 failed items
🔄 Item abc-123: retry count = 3/3
❌ Item abc-123 exceeded retry limit (3), removing from retry queue
🔄 Retry summary: 0 items to retry, 1 items exceeded limit
🔄 No items to retry for inventory
```

### **6. Detailed Statistics:**
```
📊 === RETRY STATISTICS ===
📋 Table: inventory
   Failed items: 0
   Items with retry counts: 0

📋 Table: categories
   Failed items: 1
   Items with retry counts: 1
   - xyz-789: 2/3 retries

========================
```

---

## 🧪 **How to Test the Retry Limits:**

### **Method 1: Simulate Network Failures**

1. **Disable your internet connection**
2. **Add some items** to your app (inventory/categories)
3. **Check the logs** - you should see:
   ```
   ❌ Batch sync failed for inventory: Network error
   🔄 Queuing X items for retry
   🔄 Item [uuid]: retry count incremented (0 → 1) - initial sync failure
   ```

4. **Re-enable internet** and wait for sync
5. **Check logs** - you should see retry attempts

### **Method 2: Use Debug Methods**

Add this to your app temporarily to monitor retry stats:

```dart
// In your UI, add a debug button
ElevatedButton(
  onPressed: () {
    final syncService = context.read<SyncService>();
    syncService.printRetryStats(); // This will print detailed stats
  },
  child: Text('Print Retry Stats'),
)

// Or get programmatic access
final syncService = context.read<SyncService>();
final retryStats = syncService.getRetryStats();
final failedCounts = syncService.getFailedItemsCount();
print('Retry stats: $retryStats');
print('Failed counts: $failedCounts');
```

### **Method 3: Force Failures with Wrong API**

1. **Temporarily change your API URL** to an invalid endpoint
2. **Add some items** - they will fail to sync
3. **Watch the logs** to see retry attempts
4. **After 3 failures**, items should be removed from retry queue

### **Method 4: Monitor with Flutter Inspector**

1. **Run your app in debug mode**
2. **Open Flutter Inspector**
3. **Look for debug prints** in the console
4. **Add/remove items** and watch the retry behavior

---

## 🔧 **Testing Scenarios:**

### **Scenario 1: Normal Success After Retry**
```
1. Add item → Network fails → Item queued for retry (count: 1)
2. Network restored → Retry succeeds → Retry count cleared
Result: ✅ Item synced successfully
```

### **Scenario 2: Persistent Failures**
```
1. Add item → Network fails → Item queued (count: 1)
2. Retry fails → Count incremented (count: 2)
3. Retry fails → Count incremented (count: 3)
4. Retry fails → Item removed from queue (exceeded limit)
Result: ❌ Item permanently removed from retry queue
```

### **Scenario 3: Mixed Success/Failure**
```
1. Add 3 items → All fail → All queued (count: 1 each)
2. Retry: 2 succeed, 1 fails → 2 cleared, 1 incremented (count: 2)
3. Retry: 1 succeeds → 1 cleared
Result: ✅ All items eventually synced
```

---

## 📱 **Real Device Testing:**

### **Steps:**
1. **Install app on device**
2. **Disable WiFi/mobile data**
3. **Add several items** (inventory + categories)
4. **Enable network**
5. **Watch logs** in Android Studio/Xcode or use `flutter logs`

### **Expected Behavior:**
- Items sync automatically when network is available
- Failed items retry up to 3 times
- Items exceeding retry limit are removed from queue
- Retry counts persist across app restarts

---

## 🐛 **Troubleshooting:**

### **If you don't see retry logs:**
1. **Check if sync is enabled**: Make sure `startSync()` is called
2. **Check network**: Ensure you have internet connectivity
3. **Check API**: Verify your API endpoint is working
4. **Check logs**: Look for any error messages

### **If retry limits aren't working:**
1. **Check max retry attempts**: Should be 3 by default
2. **Check SharedPreferences**: Retry counts should persist
3. **Check UUID generation**: Items need valid UUIDs
4. **Check debug prints**: Look for retry-related messages

---

## 🎯 **Verification Checklist:**

- ✅ **Initial failure**: Items are queued for retry
- ✅ **Retry attempts**: Failed items are retried up to 3 times
- ✅ **Success handling**: Retry counts are cleared on success
- ✅ **Limit enforcement**: Items exceeding limit are removed
- ✅ **Persistence**: Retry counts survive app restarts
- ✅ **Statistics**: Debug methods show correct counts
- ✅ **Logging**: Comprehensive debug output is visible

---

## 🚀 **Quick Test Commands:**

```dart
// Add this to your app for quick testing
class DebugSyncWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () => context.read<SyncService>().printRetryStats(),
          child: Text('Print Retry Stats'),
        ),
        ElevatedButton(
          onPressed: () => context.read<SyncService>().clearRetryData(),
          child: Text('Clear Retry Data'),
        ),
        ElevatedButton(
          onPressed: () {
            final stats = context.read<SyncService>().getRetryStats();
            print('Retry Stats: $stats');
          },
          child: Text('Get Retry Stats'),
        ),
      ],
    );
  }
}
```

---

## 📊 **Expected Log Output Example:**

```
🔄 Starting retry for inventory: 2 failed items
🔄 Item abc-123: retry count = 1/3
✅ Item abc-123: will retry (attempt 2/3)
🔄 Item def-456: retry count = 2/3
✅ Item def-456: will retry (attempt 3/3)
🔄 Retry summary: 2 items to retry, 0 items exceeded limit
🔄 Attempting to sync 2 items for inventory
❌ Retry sync failed for inventory: status 500
🔄 Item abc-123: retry count incremented (1 → 2)
🔄 Item def-456: retry count incremented (2 → 3)
```

**Your retry limit functionality is working correctly if you see these detailed logs!** 🎯
