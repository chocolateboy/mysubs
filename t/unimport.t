#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 11;

use mysubs test1 => sub { pass(shift) };

test1('previous scope: first sub');

{
    use mysubs
	test2 => sub { pass 'nested scope: second sub' },
	test3 => sub { pass 'nested scope: third sub' };

    test1;
    test2;
    test3;

    no mysubs qw(test1);

    ok(not(defined &test1), 'nested scope: undefined first sub');
    ok((defined &test2), 'nested scope: still defined second sub');
    ok((defined &test3), 'nested scope: still defined third sub');

    no mysubs;

    ok(not(defined &test1), 'nested scope: still undefined first sub');
    ok(not(defined &test2), 'nested scope: undefined second sub');
    ok(not(defined &test3), 'nested scope: undefined third sub');

}

test1('next scope: first sub');
