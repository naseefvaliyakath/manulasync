require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const mysql = require('mysql2/promise');
const { v4: uuidv4 } = require('uuid');
const { sendResponse , validateItem } = require('./utils');

const app = express();
const PORT = process.env.PORT || 20000;

app.use(cors());
app.use(bodyParser.json());

// MySQL pool
const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'offlineSync',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0
});

// -------------------------
// CRUD + Sync Endpoints
// -------------------------

// Get all items (not deleted)
app.get('/offlineSync/inventory', async (req, res) => {
  try {
    const [rows] = await pool.execute('SELECT * FROM inventory WHERE isDeleted = FALSE ORDER BY updatedAt DESC');
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// single sync endpoint
// single sync endpoint
app.post('/offlineSync/inventory', async (req, res) => {
  try {
    const { uuid, name, quantity, price, isDeleted, updatedAt } = req.body;

    // ✅ Validation
    const validationError = validateItem(req.body);
    if (validationError) {
      return sendResponse(res, 400, validationError, null, 'Validation Error');
    }

    // Insert or update using timestamp conflict resolution
    await pool.execute(
      `INSERT INTO inventory (uuid, name, quantity, price, updatedAt, isDeleted, isSynced)
       VALUES (?, ?, ?, ?, ?, ?, FALSE)
       ON DUPLICATE KEY UPDATE
         name = IF(VALUES(updatedAt) > updatedAt, VALUES(name), name),
         quantity = IF(VALUES(updatedAt) > updatedAt, VALUES(quantity), quantity),
         price = IF(VALUES(updatedAt) > updatedAt, VALUES(price), price),
         isDeleted = IF(VALUES(updatedAt) > updatedAt, VALUES(isDeleted), isDeleted),
         updatedAt = GREATEST(updatedAt, VALUES(updatedAt)),
         isSynced = FALSE`,
      [uuid, name || null, quantity ?? null, price ?? null, updatedAt || new Date(), isDeleted ?? false]
    );

    // Fetch the latest item after insert/update
    const [[item]] = await pool.execute('SELECT * FROM inventory WHERE uuid = ?', [uuid]);

    sendResponse(res, 201, 'Inventory item processed successfully', {
      inventoryId: item.inventoryId,
      uuid: item.uuid,
      name: item.name,
      quantity: item.quantity,
      price: item.price,
      isDeleted: item.isDeleted === 1, // return boolean
      updatedAt: item.updatedAt,
    });

  } catch (err) {
    sendResponse(res, 500, 'Server error while processing inventory item', null, err.message);
  }
});



// Batch sync endpoint
app.post('/offlineSync/inventory/batch', async (req, res) => {
  try {
    
    const { items } = req.body;

    if (!items || !Array.isArray(items) || items.length === 0) {
      return sendResponse(res, 400, 'Items array is required', null, 'Validation Error');
    }

    const errors = [];
    const processedItems = [];

    for (const item of items) {
      const validationError = validateItem(item);
      if (validationError) {
        errors.push({ uuid: item.uuid || null, error: validationError });
        continue;
      }

      const { uuid, name, quantity, price, isDeleted } = item;

      console.log(uuid,'ll')

      // Insert or update
      await pool.execute(
        `INSERT INTO inventory (uuid, name, quantity, price, updatedAt, isDeleted, isSynced)
         VALUES (?, ?, ?, ?, NOW(), ?, FALSE)
         ON DUPLICATE KEY UPDATE
           name = IF(VALUES(updatedAt) > updatedAt, VALUES(name), name),
           quantity = IF(VALUES(updatedAt) > updatedAt, VALUES(quantity), quantity),
           price = IF(VALUES(updatedAt) > updatedAt, VALUES(price), price),
           isDeleted = IF(VALUES(updatedAt) > updatedAt, VALUES(isDeleted), isDeleted),
           updatedAt = GREATEST(updatedAt, VALUES(updatedAt)),
           isSynced = FALSE`,
        [uuid, name || null, quantity ?? null, price ?? null, isDeleted ?? false]
      );

      // Fetch the latest row
      const [[savedItem]] = await pool.execute('SELECT * FROM inventory WHERE uuid = ?', [uuid]);

      processedItems.push({
        inventoryId: savedItem.inventoryId,
        uuid: savedItem.uuid,
        name: savedItem.name,
        quantity: savedItem.quantity,
        price: savedItem.price,
        isDeleted: savedItem.isDeleted === 1,
      });
    }

    sendResponse(res, 201, 'Batch sync completed', { processedItems, errors });

  } catch (err) {
    sendResponse(res, 500, 'Server error during batch sync', null, err.message);
  }
});



app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
