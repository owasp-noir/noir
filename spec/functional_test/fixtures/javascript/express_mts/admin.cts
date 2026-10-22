const express = require("express");

const app = express();

app.post("/admin/login", (req, res) => {
  res.send(req.body.user);
});
