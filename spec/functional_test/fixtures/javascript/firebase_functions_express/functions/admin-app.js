const express = require("express");
const app = express();

app.post("/ban", (req, res) => {
  const { uid } = req.body;
  res.json({ uid });
});

module.exports = app;
