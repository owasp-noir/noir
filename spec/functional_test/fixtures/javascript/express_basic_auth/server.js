const express = require("express");
const { apiAuth, docsAccess, logStatus } = require("./lib/auth");
const { builtOnly, runGated, outbound, sizeLimit, callerCheck } = require("./lib/edge");

const basicAuth = require("express-basic-auth");
const exportedAuth = require("./lib/mount");
const { needsSession } = require("./lib/mount");

const app = express();
const auth = basicAuth({ users: { admin: "x" }, challenge: true });
app.get("/metrics", apiAuth, (req, res) => res.send("ok"));
app.get("/docs", docsAccess, (req, res) => res.send("docs"));
app.get("/open", logStatus, (req, res) => res.send("open"));
app.get("/built-only", builtOnly, (req, res) => res.send("1"));
app.get("/run-gated", runGated, (req, res) => res.send("2"));
app.get("/outbound", outbound, (req, res) => res.send("3"));
app.post("/size-limit", sizeLimit, (req, res) => res.send("4"));
app.get("/caller-check", callerCheck, (req, res) => res.send("5"));
app.get("/inline-mount", basicAuth({ users: { admin: "x" } }), (req, res) => res.send("6"));
app.get("/var-mount", auth, (req, res) => res.send("7"));
app.get("/exported-mount", exportedAuth, (req, res) => res.send("8"));
app.get("/session-403", needsSession, (req, res) => res.send("9"));

app.listen(3000);
