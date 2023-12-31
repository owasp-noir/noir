require('express')

module.exports = function(app) {
    app.get('/',function(req,res){ 
        var userAgent = req.header('X-API-Key');
        var paramName = req.query.name;
        
        res.render('index');
    });
    app.post('/upload',function(req,res){ 
        res.render('index');
        var auth = req.cookies.auth;
        const name = req.body.name;
    });
}