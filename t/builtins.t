#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 11;

my $error = qr{^Modification of a read-only value attempted};

eval { chomp undef };
like($@, $error, 'builtin chomp in previous scope');

{
    use mysubs chomp => sub {
        my $name = shift || 'chomp undef';
        unlike($name, qr{^redefine}, $name);
    };

    chomp undef;
    chomp 'scope';
    chomp('scope with parens');

    {
        chomp 'nested scope';
        chomp('nested scope with parens');

        use mysubs chomp => sub {
            my $name = shift;
            like($name, qr{^redefine}, $name);
        };

        chomp 'redefine';
        chomp('redefine with parens');
    }

    chomp 'scope again';
    chomp('scope again with parens');
}

eval { chomp undef };
like($@, $error, 'builtin chomp in next scope');
