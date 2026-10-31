const express = require("express");
const { apiAuth, docsAccess, logStatus } = require("./lib/auth");

const app = express();
app.get("/metrics", apiAuth, (req, res) => res.send("ok"));
app.get("/docs", docsAccess, (req, res) => res.send("docs"));
app.get("/open", logStatus, (req, res) => res.send("open"));

app.listen(3000);
