#!/usr/bin/env perl
use Mojolicious::Lite -signatures;

get '/hello' => sub ($c) {
  my $message = GreetingService::build($c->param('name'));
  Audit->log('hello');
  $c->render(text => $message);
};

get '/inline' => sub ($c) { InlineService::call(); $c->render(text => 'ok') };

any [qw(GET POST)] => '/multi' => sub ($c) {
  my $data = MultiService->load();
  return $c->render(json => $data);
};

websocket '/echo' => sub ($c) {
  $c->on(message => sub ($c, $msg) { HiddenService::nested($msg); $c->send($msg) });
  EchoService::accepted();
};

app->start;
