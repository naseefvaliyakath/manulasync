// utils.js
function sendResponse(res, status, message, data = null, error = null) {
  return res.status(status).json({
    status,
    message,
    data,
    error,
  });
}

// Validate a single inventory item
function validateItem(item) {
  if (!item.uuid) return 'UUID is required';
  if (item.name !== undefined && typeof item.name !== 'string') return 'Name must be a string';
  if (item.quantity !== undefined && !Number.isInteger(item.quantity)) return 'Quantity must be integer';
  if (item.price !== undefined && typeof item.price !== 'string') return 'Price must be string';
  if (item.isDeleted !== undefined && typeof item.isDeleted !== 'boolean') return 'isDeleted must be boolean';
  return null;
}

module.exports = { sendResponse , validateItem};
