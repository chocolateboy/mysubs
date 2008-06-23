#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 12;

my $error = qr{^Undefined subroutine &main::test called at};

ok(not(defined &test), 'not defined in previous scope');

{
    use mysubs test => sub {
        my $name = shift;
        unlike($name, qr{^redefine}, $name);
    };

    test 'scope';
    test('scope with parens');

    {
        BEGIN {
            test 'nested scope';
            test('nested scope with parens');
        }

        use mysubs foo => sub {
            pass(shift);
        };

        use mysubs test => sub {
            my $name = shift;
            like($name, qr{^redefine}, $name);
        };

        foo 'nested sub';
        foo('nested sub with parens');

        test 'redefine';
        test('redefine with parens');
    }

    test 'scope again';
    test('scope again with parens');
}

ok(not(defined &test), 'not defined in next scope');
