const express = require('express');

// The destructuring default is a Windows path whose trailing separator is an
// escaped backslash. A quoted-run tracker that decides a string ended by
// looking one character back reads the `\\'` at the end as an escaped quote,
// so the literal never closes, the comma after it is never seen, and
// `createUploadRouter` is never registered as an import — which drops the
// mount and leaves the upload routes unprefixed.
const { UPLOAD_ROOT = 'C:\\uploads\\', createUploadRouter } = require('./routes/uploads');

const app = express();

app.use('/uploads', createUploadRouter());

app.get('/config', (req, res) => res.json({ root: UPLOAD_ROOT }));

app.listen(3000);
