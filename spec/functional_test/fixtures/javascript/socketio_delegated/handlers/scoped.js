// Prefixes resolve in the scope of their use; a reassigned one is not
// guessed.
let shifting = "a_";

function registerScoped(socket) {
    const prefix = "inner_";
    socket.on(prefix + "evt", () => {});
    socket.on(shifting + "first", () => {});
    shifting = "b_";
}

function other(socket) {
    const prefix = "other_";
    return prefix;
}

module.exports = { registerScoped, other };
