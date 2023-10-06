require('express')

module.exports = function(app) {
    app.get('/',function(req,res){ 
        res.render('index');
    });
    app.post('/upload',function(req,res){ 
        res.render('index');
    });
}