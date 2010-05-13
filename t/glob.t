#!/usr/bin/env perl

# ensure other glob slots aren't clobbered

use strict;
use warnings;

use Test::More tests => 16;

use vars qw($foo @foo %foo);

BEGIN {
    $foo = undef;
    @foo = (undef);
    %foo = (key => undef);
}

sub is_foo($$) {
    use mysubs foo => sub { [ $foo, \@foo, \%foo ] };

    my ($want, $iteration) = @_;

    is($foo, $want, "\$foo is the expected value ($iteration time)");
    is_deeply(\@foo, [ $want ], "\@foo is the expected value ($iteration time)");
    is_deeply(\%foo, { key => $want }, "\%foo is the expected value ($iteration time)");

    is_deeply(foo(), [ $foo, \@foo, \%foo ], "sub returns [ \$foo, \\\@foo, \\%foo ] ($iteration time)");
    is_deeply(foo(), [ $want, [ $want ], { key => $want } ], "sub returns expected value ($iteration time)");

    is($foo, $want, "\$foo is still the expected value ($iteration time)");
    is_deeply(\@foo, [ $want ], "\@foo is still the expected value ($iteration time)");
    is_deeply(\%foo, { key => $want }, "\%foo is still the expected value ($iteration time)");
}

is_foo(undef, 'first');

$foo = 42;
$foo[0] = 42;
$foo{key} = 42;

is_foo(42, 'second');
