const express = require("express");
const cors = require("cors");
const bodyParser = require("body-parser");
const { PrismaClient } = require("@prisma/client");
const { sendResponse, validateItem } = require("./utils");

const app = express();
const prisma = new PrismaClient();
const PORT = process.env.PORT || 20000;

// Middleware
app.use(cors());
app.use(bodyParser.json());

/**
 * Custom error handler middleware
 */
function errorHandler(err, req, res, next) {
  sendResponse(res, 500, "Internal server error", null, err.message);
}

// -------------------------
// CRUD + Sync Endpoints
// -------------------------

// ✅ Get all items (not deleted)
app.get("/offlineSync/inventory", async (req, res) => {
  try {
    const items = await prisma.inventory.findMany({
      where: { isDeleted: false },
      orderBy: { updatedAt: "desc" },
    });
    sendResponse(res, 200, "Fetched inventory items", items);
  } catch (err) {
    errorHandler(err, req, res);
  }
});

// GET changes since last sync old
// app.get('/offlineSync/inventory/changes', async (req, res) => {
//   try {
//     const { since } = req.query;

//     if (!since || typeof since !== 'string') {
//       return sendResponse(res, 400, 'Query param "since" (ISO datetime) is required', null, 'Validation Error');
//     }

//     const sinceDate = new Date(since);
//     if (isNaN(sinceDate.getTime())) {
//       return sendResponse(res, 400, 'Invalid "since" datetime format', null, 'Validation Error');
//     }

//     // ✅ Fetch all items updated after "since"
//     const changes = await prisma.inventory.findMany({
//       where: {
//         updatedAt: { gt: sinceDate },
//       },
//       orderBy: { updatedAt: 'asc' },
//     });

//     sendResponse(res, 200, 'Changes fetched successfully', { changes });
//   } catch (err) {
//     sendResponse(res, 500, 'Server error fetching changes', null, err.message);
//   }
// });

// ✅ Single sync endpoint
app.post("/offlineSync/inventory", async (req, res) => {
  try {
    const { uuid, name, quantity, price, isDeleted, updatedAt } = req.body;

    // Validation
    const validationError = validateItem(req.body);
    if (validationError) {
      return sendResponse(res, 400, validationError, null, "Validation Error");
    }

    const item = await prisma.inventory.upsert({
      where: { uuid },
      update: {
        name,
        quantity,
        price,
        isDeleted: isDeleted !== undefined ? isDeleted : false,
        updatedAt: updatedAt ? new Date(updatedAt) : new Date(),
        isSynced: false,
      },
      create: {
        uuid,
        name,
        quantity,
        price,
        isDeleted: isDeleted !== undefined ? isDeleted : false,
        updatedAt: updatedAt ? new Date(updatedAt) : new Date(),
        isSynced: false,
      },
    });

    sendResponse(res, 201, "Inventory item processed successfully", item);
  } catch (err) {
    errorHandler(err, req, res);
  }
});

// // ✅ Batch sync endpoint - Optimized old
// app.post("/offlineSync/inventory/batch", async (req, res) => {
//   try {
//     const { items } = req.body;

//     if (!Array.isArray(items) || items.length === 0) {
//       return sendResponse(res, 400, "Items array is required");
//     }

//     const errors = [];
//     const processedItems = [];

//     await prisma.$transaction(async (tx) => {
//       for (const item of items) {
//         try {
//           const validationError = validateItem(item);
//           if (validationError) {
//             errors.push({ uuid: item.uuid || null, error: validationError });
//             continue;
//           }

//           const { uuid, name, quantity, price, isDeleted, updatedAt } = item;
//           const incomingUpdatedAt = new Date(updatedAt);

//           // 🗑️ DELETE OPERATION: Always process deletes regardless of timestamp
//           if (isDeleted) {
//             await tx.inventory.updateMany({
//               where: { uuid },
//               data: { isDeleted: true, updatedAt: new Date(), isSynced: false }
//             });
//             // Retrieve the deleted item to return in response
//             const deletedItem = await tx.inventory.findUnique({ where: { uuid } });
//             // If item was found and deleted, add to results; otherwise create delete record
//             processedItems.push(deletedItem || { uuid, isDeleted: true, updatedAt: new Date() });
//             continue;
//           }

//           // 🔄 UPDATE OPERATION: Only update if incoming data is newer than existing data
//           const updateResult = await tx.inventory.updateMany({
//             where: { uuid, updatedAt: { lt: incomingUpdatedAt } },
//             data: { name, quantity, price, isDeleted: false, updatedAt: incomingUpdatedAt, isSynced: false }
//           });

//           // ✅ UPDATE SUCCESS: Item was updated (incoming data was newer)
//           if (updateResult.count > 0) {
//              // Retrieve the updated item to return in response
//             const updatedItem = await tx.inventory.findUnique({ where: { uuid } });
//             processedItems.push(updatedItem);
//           } else {
//             // ❌ UPDATE SKIPPED: Incoming data wasn't newer, check if item exists
//             const existing = await tx.inventory.findUnique({ where: { uuid } });
//             if (existing) {
//             // 📋 ITEM EXISTS BUT NEWER: Keep existing item (no update needed)
//               processedItems.push(existing);
//             } else {
//             // ➕ ITEM DOESN'T EXIST: Create new item in database
//             const newItem = await tx.inventory.create({
//                 data: { uuid, name, quantity, price, isDeleted: false, updatedAt: incomingUpdatedAt, isSynced: false }
//               })
//               processedItems.push(newItem);
//             }
//           }
//         } catch (error) {
//         // ⚠️ ERROR HANDLING: Record error but continue processing other items
//           errors.push({ uuid: item.uuid || null, error: error.message });
//         }
//       }
//     });

//     // ONLY 2 LOGS: Final results
//     console.log("Batch sync completed:", processedItems.length, "items processed,", errors.length, "errors");
    
//     sendResponse(res, 201, "Batch sync completed", { processedItems, errors });
//   } catch (err) {
//     console.error("Batch sync failed:", err.message); // Only error log
//     errorHandler(err, req, res);
//   }
// });




// Generic sync endpoints for any table with fields: uuid, updatedAt, isDeleted, isSynced
// Assumes Prisma models have a primary key ending with 'Id' (e.g., inventoryId)
// and a unique 'uuid' field.

// Generic sync endpoints for any table with fields: uuid, updatedAt, isDeleted, isSynced
const allowedTables = {
  inventory: (tx) => tx.inventory,
  categories: (tx) => tx.categories,  // ✅ Added category support
};

// Only essential safety: prevent server overload
const MAX_BATCH_SIZE = 1000;

function getModel(tx, tableName) {
  const getter = allowedTables[tableName];
  if (!getter) return null;
  return getter(tx);
}

function validateItemCommon(item) {
  if (!item || typeof item !== 'object') return 'Item must be an object';
  if (!item.uuid || typeof item.uuid !== 'string') return 'uuid is required';
  if (!item.updatedAt) return 'updatedAt is required';
  const d = new Date(item.updatedAt);
  if (Number.isNaN(d.getTime())) return 'updatedAt must be ISO datetime';
  if (typeof item.isDeleted !== 'boolean' && item.isDeleted !== undefined) {
    return 'isDeleted must be boolean';
  }
  return null;
}

function stripReservedFields(item) {
  const reserved = new Set(['uuid', 'serverId', 'updatedAt', 'isDeleted', 'isSynced']);
  const out = {};
  for (const [k, v] of Object.entries(item)) {
    if (!reserved.has(k)) out[k] = v;
  }
  return out;
}

function addServerId(record) {
  if (!record) return record;
  if (record.serverId == null) {
    const idKey = Object.keys(record).find((k) => k !== 'uuid' && k.endsWith('Id'));
    if (idKey) {
      return { ...record, serverId: String(record[idKey]) };
    }
  }
  return record;
}

// POST /offlineSync/:table/batch
app.post('/offlineSync/:table/batch', async (req, res) => {
  try {
    const table = String(req.params.table);
    const items = req.body?.items;

    // ESSENTIAL SAFETY: Prevent server overload
    if (!Array.isArray(items)) {
      return sendResponse(res, 400, 'Items array is required');
    }
    if (items.length > MAX_BATCH_SIZE) {
      return sendResponse(res, 400, `Maximum ${MAX_BATCH_SIZE} items per request`);
    }
    if (items.length === 0) {
      return sendResponse(res, 200, 'No items to process', { 
        processedItems: [], 
        errors: [] 
      });
    }

    const errors = [];
    const processedItems = [];

    // Your perfect logic - unchanged!
    await prisma.$transaction(async (tx) => {
      const model = getModel(tx, table);
      if (!model) {
        throw new Error(`Unsupported table: ${table}`);
      }

      for (const item of items) {
        try {
          const e = validateItemCommon(item);
          if (e) {
            errors.push({ uuid: item?.uuid ?? null, error: e });
            continue;
          }

          const { uuid } = item;
          const incomingUpdatedAt = new Date(item.updatedAt);
          const isDeleted = !!item.isDeleted;
          const rest = stripReservedFields(item);

          if (isDeleted) {
            await model.updateMany({
              where: { uuid },
              data: { isDeleted: true, updatedAt: incomingUpdatedAt, isSynced: false },
            });
            const deleted = await model.findUnique({ where: { uuid } });
            processedItems.push(addServerId(deleted || { uuid, isDeleted: true, updatedAt: incomingUpdatedAt }));
            continue;
          }

          // Update only if incoming is newer
          const updated = await model.updateMany({
            where: { uuid, updatedAt: { lt: incomingUpdatedAt } },
            data: { ...rest, isDeleted: false, updatedAt: incomingUpdatedAt, isSynced: false },
          });

          if (updated.count > 0) {
            const rec = await model.findUnique({ where: { uuid } });
            processedItems.push(addServerId(rec));
          } else {
            const existing = await model.findUnique({ where: { uuid } });
            if (existing) {
              processedItems.push(addServerId(existing));
            } else {
              const created = await model.create({
                data: { uuid, ...rest, isDeleted: false, updatedAt: incomingUpdatedAt, isSynced: false },
              });
              processedItems.push(addServerId(created));
            }
          }
        } catch (err) {
          errors.push({ uuid: item?.uuid ?? null, error: err.message });
        }
      }
    }); // No timeout config - keeping it simple!

    console.log('Batch sync completed:', processedItems.length, 'items processed,', errors.length, 'errors');
    return sendResponse(res, 201, 'Batch sync completed', { processedItems, errors });
  } catch (err) {
    console.error('Batch sync failed:', err.message);
    return errorHandler(err, req, res);
  }
});



// Use error handler middleware globally
app.use(errorHandler);

app.listen(PORT, () => console.log(`✅ Server running on port ${PORT}`));



// // GET /offlineSync/:table/changes?since=ISO
app.get('/offlineSync/:table/changes', async (req, res) => {
  try {
    const table = String(req.params.table);
    const since = String(req.query.since || '');
    const sinceDate = new Date(since);
    if (!since || Number.isNaN(sinceDate.getTime())) {
      return sendResponse(res, 400, 'Query param "since" (ISO datetime) is required', null, 'Validation Error');
    }

    const model = getModel(prisma, table);
    if (!model) {
      return sendResponse(res, 404, `Unsupported table: ${table}`);
    }

    const changesRaw = await model.findMany({
      where: { updatedAt: { gt: sinceDate } },
      orderBy: { updatedAt: 'asc' },
    });

    const changes = changesRaw.map(addServerId);
    return sendResponse(res, 200, 'Changes fetched successfully', { changes });
  } catch (err) {
    return sendResponse(res, 500, 'Server error fetching changes', null, err.message);
  }
});




// CREATE TABLE categories (
//   id INT AUTO_INCREMENT PRIMARY KEY,
//   uuid VARCHAR(255) UNIQUE NOT NULL,
//   name VARCHAR(255) NOT NULL,
//   updatedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
//   isDeleted BOOLEAN DEFAULT FALSE,
//   isSynced BOOLEAN DEFAULT FALSE,
//   createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
//   INDEX idx_uuid (uuid),
//   INDEX idx_updatedAt (updatedAt),
//   INDEX idx_isDeleted (isDeleted)
// );