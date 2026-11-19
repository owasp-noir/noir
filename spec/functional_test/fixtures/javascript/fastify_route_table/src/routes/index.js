const carController = require('../controllers/carController');

const routes = [
  {
    method: 'GET',
    url: '/api/cars',
    handler: carController.getCars,
  },
  {
    method: 'POST',
    url: '/api/cars',
    handler: carController.addCar,
  },
  {
    method: 'DELETE',
    url: '/api/cars/:id',
    handler: carController.deleteCar,
  },
];

module.exports = routes;
