const express = require('express');
const files = require('./routes/files');
const app = express();
app.use('/files', files);
app.listen(3000);
