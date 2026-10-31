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

// A 403 for a session without a cart: not about the caller.
function needsCart(req, res, next) {
    if (!req.session.cart) {
        return sendError(res, 403, "cart is empty");
    }
    next();
}

module.exports = basicAuth({ users: { admin: "x" }, challenge: true });
module.exports.needsSession = needsSession;
module.exports.needsCart = needsCart;
