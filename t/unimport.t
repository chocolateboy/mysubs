#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 11;

use mysubs test1 => sub { pass(shift) };

test1('previous scope: test1');

{
    use mysubs
        test2 => sub { pass 'nested scope: test2' },
        test3 => sub { pass 'nested scope: test3' };

    BEGIN {
        test1('nested scope: test1');
        test2;
        test3;
    }

    no mysubs qw(test1);

    BEGIN {
        ok(not(defined &test1), 'nested scope: undefined test1');
        ok((defined &test2), 'nested scope: still defined test2');
        ok((defined &test3), 'nested scope: still defined test3');
    }

    no mysubs;

    BEGIN {
        ok(not(defined &test1), 'nested scope: still undefined test1');
        ok(not(defined &test2), 'nested scope: undefined test2');
        ok(not(defined &test3), 'nested scope: undefined test3');
    }
}

test1('next scope: test1');
