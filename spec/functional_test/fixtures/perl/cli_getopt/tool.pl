use strict;
use warnings;
use Getopt::Long;

my $port;
my $verbose;
GetOptions(
    "port=i"  => \$port,
    "verbose" => \$verbose,
);

my $token = $ENV{API_TOKEN};
my $first = $ARGV[0];
print "$port $verbose $token $first\n";
