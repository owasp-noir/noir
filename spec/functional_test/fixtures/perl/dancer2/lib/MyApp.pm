package MyApp;
use Dancer2;

our $VERSION = '0.1';

# --- Basic verbs -----------------------------------------------------------

get '/' => sub {
    my $page = query_parameters->get('page');
    template 'index';
};

get '/search' => sub {
    my $q     = query_parameters->get('q');
    my $limit = query_parameters->get('limit');
    return "searching for $q";
};

post '/users' => sub {
    my $name  = body_parameters->get('name');
    my $email = body_parameters->get('email');
    return "user created";
};

# Named placeholder with a type constraint (the `[Int]` is dropped from
# the displayed URL but the `:id` placeholder is kept).
put '/users/:id[Int]' => sub {
    my $id   = route_parameters->get('id');
    my $name = body_parameters->get('name');
    return "user updated";
};

patch '/users/:id' => sub {
    my $id = route_parameters->get('id');
    return "user patched";
};

# `del`, not `delete` — the Dancer2 DELETE keyword.
del '/users/:id' => sub {
    my $id = route_parameters->get('id');
    return "user deleted";
};

options '/health' => sub {
    return "";
};

# Header + cookie inputs.
get '/profile' => sub {
    my $auth    = request->header('Authorization');
    my $session = cookie('session_id');
    return "profile";
};

# Multipart upload.
post '/upload' => sub {
    my $file = upload('document');
    return "uploaded";
};

# Legacy mixed-source accessor; POST buckets it as a form param.
post '/login' => sub {
    my $user = param('username');
    my $pass = param('password');
    return "ok";
};

# --- any -------------------------------------------------------------------

any ['get', 'post'] => '/feedback' => sub {
    return "feedback";
};

any '/wildcard' => sub {
    return "matches every verb";
};

# `any ['delete']` — full HTTP spelling (Dancer2 normalizes it like `del`),
# so this is a DELETE-only route, not an expand-to-everything fallback.
any ['delete'] => '/cache' => sub {
    return "cache cleared";
};

# `any ['head']` — HEAD-only route via the list form.
any ['head'] => '/heartbeat' => sub {
    return "";
};

# Bare `any` with a legacy `param`: read verbs (GET/HEAD/OPTIONS) bucket it
# as a query param, write verbs (POST/PUT/DELETE/PATCH) as a form param —
# resolved per generated method.
any '/notify' => sub {
    my $msg = param('message');
    return "queued";
};

# --- wildcards & regex routes ---------------------------------------------

get '/files/*' => sub {
    my ($path) = splat;
    return "file";
};

get qr{/ticket/(?<code>[0-9]+)} => sub {
    my $code = captures->{code};
    return "ticket";
};

# --- block-scoped prefix (nested) -----------------------------------------

prefix '/api' => sub {
    get '/status' => sub {
        return "ok";
    };

    post '/tokens' => sub {
        my $scope = body_parameters->get('scope');
        return "token";
    };

    prefix '/v2' => sub {
        get '/ping' => sub {
            return "pong";
        };
    };
};

# --- procedural prefix -----------------------------------------------------

prefix '/admin';

get '/dashboard' => sub {
    return "dashboard";
};

post '/settings' => sub {
    my $key = body_parameters->get('key');
    return "settings saved";
};

prefix undef;

get '/ping' => sub {
    return "pong";
};

1;

__END__

=head1 NAME

MyApp - Dancer2 analyzer fixture.

=head1 SYNOPSIS

  # Example wiring inside POD must NOT be picked up as a real route.
  get '/should-not-appear-in-pod' => sub { 'nope' };
  post '/another-pod-fake' => sub { 'nope' };

=cut
