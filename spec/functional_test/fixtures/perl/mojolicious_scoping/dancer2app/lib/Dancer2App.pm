package Dancer2App;

# A Dancer2 service that shares a checkout with the Mojolicious app next
# door. None of it belongs to `perl_mojolicious`: the `query_parameters->get`
# / `body_parameters->get` accessors are Dancer2 request reads, and the
# `get '/status'` keyword routes carry Dancer2's own `prefix`.
use Dancer2;

prefix '/api';

get '/status' => sub {
    my $page  = query_parameters->get('page');
    my $limit = query_parameters->get('limit');
    return { ok => 1 };
};

get '/dashboard' => sub {
    my $q = query_parameters->get('q');
    return { ok => 1 };
};

post '/settings' => sub {
    my $email = body_parameters->get('email');
    return { ok => 1 };
};

1;
