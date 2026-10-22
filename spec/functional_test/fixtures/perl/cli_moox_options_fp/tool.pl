use strict;
use warnings;
use Getopt::Long;

my $port;
GetOptions("port=i" => \$port);

# Unrelated bareword sub literally named `option`, nothing to do with the
# MooX options-declaration library. This file has no dependency on it.
sub option {
    my ($name, %args) = @_;
    return $args{default};
}

my $t = option 'timeout' => (default => 30);

print "$port $t\n";
