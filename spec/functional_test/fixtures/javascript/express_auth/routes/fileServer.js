const path = require('path');

// A factory whose closure answers the request itself: mounted with
// `app.use('/ftp/:file', servePublicFiles())`, it is a route, not a guard.
function servePublicFiles() {
  return ({ params }, res, next) => {
    const file = params.file;

    if (!file.includes('/')) {
      res.sendFile(path.resolve('ftp/', file));
    } else {
      res.status(403);
      next(new Error('File names cannot contain forward slashes!'));
    }
  };
}

module.exports = { servePublicFiles };
