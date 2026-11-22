const helpers = module.exports;
require('./body-reader')(helpers);

helpers.forward = function (payload) {
    return helpers.read(payload);
};
