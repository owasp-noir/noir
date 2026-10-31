const expressBasicAuth = require("express-basic-auth");
const { Settings } = require("./settings");
const { currentUser } = require("./ctx");

// Builds the middleware and never runs it.
async function builtOnly(req, res, next) {
    const mw = expressBasicAuth({ users: { admin: "x" }, challenge: true });
    next();
}

// Built first, run only when a setting allows.
async function runGated(req, res, next) {
    const middleware = expressBasicAuth({ users: { admin: "x" }, challenge: true });
    const disabledAuth = await Settings.get("disableAuth");
    if (!disabledAuth) {
        middleware(req, res, next);
    } else {
        next();
    }
}

// A local helper of the same name that builds an outbound header.
function basicAuth({ user, pass }) {
    return "Basic " + Buffer.from(user + ":" + pass).toString("base64");
}

function outbound(req, res, next) {
    req.upstreamAuth = basicAuth({ user: "svc", pass: process.env.UPSTREAM_PASS });
    next();
}

function sendJson(res, status, msg) {
    res.status(status).json({ msg });
}

// A 403 about the payload, not the caller.
function sizeLimit(req, res, next) {
    if (req.body.length > 1024) {
        return sendJson(res, 403, "payload too large");
    }
    next();
}

// Awaits the caller, not a setting.
async function callerCheck(req, res, next) {
    if (!(await currentUser())) {
        return res.status(401).json({ msg: "login" });
    }
    next();
}

module.exports = { builtOnly, runGated, outbound, sizeLimit, callerCheck };
