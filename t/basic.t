#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 12;

my $error = qr{^Undefined subroutine &main::test called at};

eval { test('fail') };
like ($@, $error, 'not defined in previous scope');

{
    use mysubs test => sub {
        my $name = shift;
        pass($name) unless ($name =~ /^redefine/);
    };

    test 'scope';
    test('scope with parens');

    {
        test 'nested scope';
        test('nested scope with parens');

        use mysubs foo => sub {
            pass(shift);
        };

        use mysubs test => sub {
            my $name = shift;
            pass($name) if ($name =~ /^redefine/);
        };

        foo 'nested sub';
        foo('nested sub with parens');

        test 'redefine';
        test('redefine with parens');
    }

    test 'scope again';
    test('scope again with parens');
}

eval { test('fail') };
like ($@, $error, 'not defined in next scope');
