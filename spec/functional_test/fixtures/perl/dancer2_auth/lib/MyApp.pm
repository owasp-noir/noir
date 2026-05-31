package MyApp;
use Dancer2;
use Dancer2::Plugin::Auth::Extensible;

get '/admin' => require_role Admin => sub {
    return "admin area";
};

get '/me' => require_login sub {
    return "profile";
};

post '/reports' => require_any_role ['Admin', 'Auditor'] => sub {
    return "reports";
};

get '/dashboard' => sub {
    my $user = logged_in_user;
    return "dashboard" if $user;
    redirect '/login';
};

get '/public' => sub {
    return "public, no auth required";
};

1;
