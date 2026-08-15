<?php
use Phalcon\Mvc\Micro;
use Phalcon\Mvc\Micro\Collection as MicroCollection;

$app = new Micro();

$app->get('/', function () {
    echo 'Hello';
});

$app->get('/search', function () {
    $q = $this->request->getQuery('q');
});

$app->post('/users', function () {
    $name = $this->request->getPost('name');
});

$app->get('/users/{id}', function ($id) {
    $token = $this->request->getHeader('X-Auth-Token');
});

$app->put('/users/{id}', function ($id) {
});

$app->delete('/users/{id}', function ($id) {
});

$app->map('/login', function () {
    $session = $this->cookies->get('session');
})->via(['GET', 'POST']);

$invoices = new MicroCollection();
$invoices->setHandler(new InvoicesController());
$invoices->setPrefix('/invoices');
$invoices->get('/view/{id}', 'view');
$invoices->post('/add', 'add');

$app->mount($invoices);

$app->run();
