#!/usr/bin/env perl
use Mojolicious::Lite -signatures;

# Basic route
get '/hello' => sub ($c) {
  $c->render(text => 'Hello, World!');
};

# Query parameters
get '/search' => sub ($c) {
  my $q     = $c->param('q');
  my $limit = $c->req->query_params->param('limit');
  $c->render(text => "Searching for $q");
};

# Form/body parameters
post '/users' => sub ($c) {
  my $name  = $c->req->body_params->param('name');
  my $email = $c->param('email');
  $c->render(text => 'User created');
};

# Login (form params via param helper, POST → form)
post '/login' => sub ($c) {
  my $username = $c->param('username');
  my $password = $c->param('password');
  $c->render(text => 'Logged in');
};

# Header parameters
get '/protected' => sub ($c) {
  my $auth   = $c->req->headers->header('Authorization');
  my $apikey = $c->req->headers->header('X-Api-Key');
  $c->render(text => 'Protected');
};

# Cookie parameters
get '/profile' => sub ($c) {
  my $session = $c->cookie('session_id');
  my $pref    = $c->req->cookie('user_preference');
  $c->render(text => 'Profile');
};

# Path parameters
put '/users/:id' => sub ($c) {
  $c->render(text => 'Updated');
};

patch '/users/:id/profile' => sub ($c) {
  $c->render(text => 'Patched');
};

delete '/users/:id' => sub ($c) {
  $c->render(text => 'Deleted');
};

# OPTIONS / HEAD
options '/health' => sub ($c) {
  $c->render(text => '');
};

# Wildcard placeholder
get '/files/*path' => sub ($c) {
  $c->render(text => 'File');
};

# WebSocket
websocket '/echo' => sub ($c) {
  $c->on(message => sub ($c, $msg) { $c->send($msg) });
};

# Multi-method `any` with method list
any [qw(GET POST)] => '/multi' => sub ($c) {
  $c->render(text => 'multi');
};

app->start;
