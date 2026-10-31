const { AsyncLocalStorage } = require("async_hooks");
const store = new AsyncLocalStorage();

async function currentUser() {
    return store.getStore()?.user;
}

module.exports = { currentUser, store };
