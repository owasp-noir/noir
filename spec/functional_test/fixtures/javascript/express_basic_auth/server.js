const express = require("express");
const { apiAuth, docsAccess, logStatus } = require("./lib/auth");
const { builtOnly, runGated, outbound, sizeLimit, callerCheck } = require("./lib/edge");

const app = express();
app.get("/metrics", apiAuth, (req, res) => res.send("ok"));
app.get("/docs", docsAccess, (req, res) => res.send("docs"));
app.get("/open", logStatus, (req, res) => res.send("open"));
app.get("/built-only", builtOnly, (req, res) => res.send("1"));
app.get("/run-gated", runGated, (req, res) => res.send("2"));
app.get("/outbound", outbound, (req, res) => res.send("3"));
app.post("/size-limit", sizeLimit, (req, res) => res.send("4"));
app.get("/caller-check", callerCheck, (req, res) => res.send("5"));

app.listen(3000);
