#!/usr/bin/env perl

use Devel::Pragma;

use strict;
use warnings;

use if (-d 't'), lib => 't';

use Test::More tests => 10;

ok(not(defined &test1), 'test1 not defined in previous scope');
ok(not(defined &test2), 'test2 not defined in previous scope');

{
    use test_4;
    use test_6;

    test1();
    test2();

    no test_4;

    ok(not(defined &test1), 'unimported test1');
    ok((defined &test2), "haven't unimported test2");

    no test_6;

    ok(not(defined &test1), 'test1 still unimported');
    ok(not(defined &test2), 'test2 now unimported');
}

ok(not(defined &test1), 'test1 not defined in next scope');
ok(not(defined &test1), 'test2 not defined in next scope');
