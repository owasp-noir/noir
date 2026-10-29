const Hapi = require('@hapi/hapi');
const HauteCouture = require('@hapipal/haute-couture');
exports.plugin = { name: 'app', register: HauteCouture.composeWith() };
