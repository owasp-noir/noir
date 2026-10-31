const expressBasicAuth = require("express-basic-auth");
const { Settings } = require("./settings");

// Basic auth unless an admin setting turns authentication off.
async function apiAuth(req, res, next) {
    if (!(await Settings.get("disableAuth"))) {
        const middleware = expressBasicAuth({ authorizer: check, challenge: true });
        middleware(req, res, next);
    } else {
        next();
    }
}

function sendText(res, status, text) {
    res.status(status).send(text);
}

async function docsAccess(req, res, next) {
    if (req.user) {
        next();
        return;
    }
    sendText(res, 401, "Log in to view the documentation.");
}

// Records every response's status: refuses nothing.
function logStatus(req, res, next) {
    res.on("finish", () => record(res, res.statusCode));
    next();
}

function check(user, password) {
    return user === "admin" && password === "secret";
}

module.exports = { apiAuth, docsAccess, logStatus };
