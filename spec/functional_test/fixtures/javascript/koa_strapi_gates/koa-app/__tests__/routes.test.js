// A unit test building a route table to feed the provider under test.
'use strict';

const routes = [
  {
    method: 'GET',
    path: '/files/:id',
    handler: 'controller.findOne',
  },
];

test('lists routes', () => {
  expect(routes).toHaveLength(1);
});
