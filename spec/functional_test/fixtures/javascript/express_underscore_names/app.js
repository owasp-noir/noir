const express = require('express');

const app = express();
require('./routes/speed_test')(app);
require('./routes/user_spec')(app);

app.listen(3000);
