#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 7;

my $error = qr{^Undefined subroutine &main::test called at};

my $previous = \&test;
eval { $previous->('fail') };
like ($@, $error, 'not defined in previous scope');

{
    use mysubs test => sub {
        my $name = shift;
        unlike($name, qr{^redefine}, $name);
    };

    my $test = \&test;

    $test->('scope');

    {
        $test->('nested scope');

        use mysubs foo => sub {
            pass(shift);
        };

        my $foo = \&foo;

        use mysubs test => sub {
            my $name = shift;
            like($name, qr{^redefine}, $name);
        };

        my $test = \&test;

        $foo->('nested sub');
        $test->('redefine');
    }

    $test->('scope again');
}

my $next = \&test;
eval { $next->('fail') };
like ($@, $error, 'not defined in next scope');
