exports.getCars = async (req, reply) => {
  return { make: req.query.make };
};
exports.addCar = async (req, reply) => {
  const { title, brand } = req.body;
  return { title, brand };
};
exports.deleteCar = async (req, reply) => {
  return { id: req.params.id };
};
