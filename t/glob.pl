#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 6;

use vars qw($foo);

sub mytest($) {
    use mysubs foo => sub { $foo };

    my $want = shift;

    is($foo, $want, '$foo is the expected value');
    is(foo(), $foo, 'sub called');
    is($foo, $want, '$foo is still the expected value');
}

mytest(undef);
$foo = 42;
mytest(42);
