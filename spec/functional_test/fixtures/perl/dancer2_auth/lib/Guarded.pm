package Guarded;
use Dancer2;
use Dancer2::Plugin::Auth::Extensible;

# Application-wide guard: protects every route declared in this package.
hook before => sub {
    redirect '/login' unless logged_in_user;
};

get '/secret' => sub {
    return "secret";
};

1;
