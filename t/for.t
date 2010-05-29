#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 10;
use FindBin qw($Bin);

use lib $Bin;

ok not(defined &foo);
ok not(defined &bar);

{
    use mysubs_for;

    is foo, 'foo';
    is bar, 'bar';

    no mysubs_for 'foo';
    ok not(defined &foo);
    ok defined(&bar);

    no mysubs_for;
    ok not(defined &foo);
    ok not(defined &bar);
}

ok not(defined &foo);
ok not(defined &bar);
