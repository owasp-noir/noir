const basicAuth = require("express-basic-auth");

function sendError(res, status, msg) {
    res.status(status).json({ msg });
}

// A 403 for a caller with no session.
function needsSession(req, res, next) {
    if (!req.session.userId) {
        return sendError(res, 403, "login required");
    }
    next();
}

module.exports = basicAuth({ users: { admin: "x" }, challenge: true });
module.exports.needsSession = needsSession;
