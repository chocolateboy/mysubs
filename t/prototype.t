#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 18;

BEGIN { is(prototype('Foo::Bar::concat'), undef, '"Foo::Bar::concat" not prototyped in previous scope') }

{
    package Foo::Bar;

    use vars qw($error1 $error2 $error3 $error4);

    use mysubs concat => sub ($$) { join '', grep { defined } @_ };

    BEGIN {
        ::is(prototype(\&concat), '$$', 'prototype works for \&concat (compile-time)');
        ::is(prototype('concat'), '$$', 'prototype works for "concat" (compile-time)');
        ::is(prototype('Foo::Bar::concat'), '$$', 'prototype() works for "Foo::Bar::concat" (compile-time)');
        ::is(prototype("Foo'Bar'concat"), '$$', q{prototype() works for "Foo'Bar'concat" (compile-time)});
        ::is(prototype("Foo::Bar'concat"), '$$', q{prototype() works for "Foo::Bar'concat" (compile-time)});
        ::is(concat('foo', 'bar'), 'foobar',
            'prototyped sub works with correct number of arguments (compile-time)');
    }

    ::is(prototype(\&concat), '$$', 'prototype works for \&concat');
    ::is(prototype('concat'), '$$', 'prototype works for "concat"');
    ::is(prototype('Foo::Bar::concat'), '$$', 'prototype() works for "Foo::Bar::concat"');
    ::is(prototype("Foo'Bar'concat"), '$$', q{prototype() works for "Foo'Bar'concat"});
    ::is(prototype("Foo::Bar'concat"), '$$', q{prototype() works for "Foo::Bar'concat"});
    ::is(concat('foo', 'bar'), 'foobar', 'prototyped sub works with correct number of arguments');

    # we can't use Test::Exceptions, as prototype violations are trapped at compile-time
    BEGIN { eval 'concat("foo")'; $error1 = $@ }
    ::like($error1, qr/Not enough arguments for Foo::Bar::concat/, 'prototyped sub dies with too few arguments');
        
    BEGIN { eval 'concat("foo", "bar", "baz")'; $error2 = $@ }
    ::like($error2, qr/Too many arguments for Foo::Bar::concat/, 'prototyped sub dies with too many arguments');

    ::is (&concat('foo'), 'foo', '& disables prototype checking with too few arguments');
    ::is (&concat('foo', 'bar', 'baz'), 'foobarbaz', '& disables prototype checking with too many arguments');
}

is(prototype('Foo::Bar::concat'), undef, '"Foo::Bar::concat" not prototyped in next scope');
