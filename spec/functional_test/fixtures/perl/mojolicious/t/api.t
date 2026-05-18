# Regression guard: a Perl test script under `t/` (CPAN convention)
# or with a `.t` extension is test code, never a real route handler.
# Neither URL below should appear in the fixture's expected-endpoints
# list.
use Mojolicious::Lite;
use Test::More;

get '/should-not-appear-test' => sub {
    my $c = shift;
    $c->render(text => 'ok');
};

post '/should-not-appear-test' => sub {
    my $c = shift;
    $c->render(text => 'ok');
};

ok 1, 'noop test';

done_testing;
