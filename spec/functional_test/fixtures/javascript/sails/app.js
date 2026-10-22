var sails = require('sails');

sails.lift({}, function (err) {
  if (err) {
    console.error(err);
    process.exit(1);
  }
});
