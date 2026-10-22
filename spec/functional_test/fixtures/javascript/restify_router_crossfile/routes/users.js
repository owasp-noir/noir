const Router = require('restify-router').Router;
const router = new Router();
router.get('/list', (req, res, next) => { res.send('ok'); next(); });
module.exports = router;
