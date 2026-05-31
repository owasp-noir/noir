package MyApp;
use Dancer2;

get '/hello' => sub {
    my $greeting = GreetingService::build();
    Audit->log('hello');
    template('hello');
};

# Named sub declared *before* the route that references it as a code ref,
# so the analyzer must resolve callees through the named-sub index rather
# than by scanning forward from the route declaration.
sub status {
    my $info = StatusService->current;
    return to_json($info);
}

get '/status' => \&status;

prefix '/api' => sub {
    post '/login' => sub {
        my $user  = body_parameters->get('username');
        my $token = LoginService::authenticate($user);
        return to_json({ token => $token });
    };
};

1;
