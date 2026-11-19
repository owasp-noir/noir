const createItemBody = {
  type: 'object',
  required: ['sku'],
  properties: { sku: { type: 'string' }, qty: { type: 'integer' } },
};
const listQuery = {
  type: 'object',
  properties: { cursor: { type: 'string' } },
};
const createItemSchema = { body: createItemBody, querystring: listQuery };
module.exports = { createItemBody, listQuery, createItemSchema };
