const functions = require("firebase-functions");

exports.helloWorld = functions.https.onRequest((req, res) => {
  const name = req.query.name;
  const token = req.headers["x-api-key"];
  res.send(`Hello ${name}`);
});

exports.addMessage = functions
  .region("asia-northeast3")
  .runWith({ memory: "256MB" })
  .https.onCall((data, context) => {
    return { text: data.text };
  });

// exports.legacy = functions.https.onRequest((req, res) => res.end());

exports.onUserCreate = functions.auth.user().onCreate((user) => null);
