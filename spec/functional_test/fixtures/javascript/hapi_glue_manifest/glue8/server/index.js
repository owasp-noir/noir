const Glue = require('@hapi/glue');
const Manifest = require('./manifest');
exports.deployment = async () => Glue.compose(Manifest, { relativeTo: __dirname });
