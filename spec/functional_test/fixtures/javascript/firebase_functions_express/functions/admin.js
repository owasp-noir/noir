const { onRequest } = require("firebase-functions/v2/https");
const adminApp = require("./admin-app");

exports.admin = onRequest({ region: "us-central1" }, adminApp);
