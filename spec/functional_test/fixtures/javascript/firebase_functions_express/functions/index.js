const functions = require("firebase-functions");
const express = require("express");

const app = express();
app.get("/users/:id", (req, res) => res.json({ id: req.params.id }));

exports.api = functions.https.onRequest(app);
