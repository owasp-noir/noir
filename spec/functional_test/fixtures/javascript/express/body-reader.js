module.exports = function (helpers) {
    helpers.read = function (input) {
        const { display: caption } = input;
        return [caption, input['locale'], input.server, input.replaced];
    };
};
