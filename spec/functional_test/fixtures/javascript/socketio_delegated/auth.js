function checkLogin(socket) {
    if (!socket.userID) {
        throw new Error("You are not logged in.");
    }
}

// Refuses a socket that HAS the property: not an authentication check.
function checkBanned(socket) {
    if (socket.banned) throw new Error("banned");
}

// Hands the socket on to the real check.
function requireLogin(socket) {
    checkLogin(socket);
}

module.exports = { checkLogin, checkBanned, requireLogin };
