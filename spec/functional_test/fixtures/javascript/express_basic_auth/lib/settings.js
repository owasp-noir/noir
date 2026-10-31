const values = new Map();

module.exports.Settings = {
    async get(key) {
        return values.get(key);
    },
};
