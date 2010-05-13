#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 27;

our @WARNINGS;

BEGIN { require mysubs; mysubs::start_trace() }
BEGIN { $SIG{__WARN__} = sub { my $warning = join '', @_; push (@WARNINGS, $warning) if ($warning =~ /^mysubs: /) } }

BEGIN { is(prototype('Foo::Bar::concat'), undef, '"Foo::Bar::concat" not prototyped in previous scope (compile-time)') }
is(prototype('Foo::Bar::concat'), undef, '"Foo::Bar::concat" not prototyped in previous scope (runtime)');

{
    package Foo::Bar;

    our ($error1, $error2);

    use mysubs concat => sub ($$) { join '', grep { defined } @_ };

    BEGIN {
        ::is(prototype(\&concat), '$$', 'prototype works for \&concat (compile-time)');
        ::is(prototype('concat'), '$$', 'prototype works for "concat" (compile-time)');
        ::is(prototype('Foo::Bar::concat'), '$$', 'prototype() works for "Foo::Bar::concat" (compile-time)');
        ::is(prototype("Foo'Bar'concat"), '$$', q{prototype() works for "Foo'Bar'concat" (compile-time)});
        ::is(prototype("Foo'Bar::concat"), '$$', q{prototype() works for "Foo'Bar::concat" (compile-time)});
        ::is(prototype("Foo::Bar'concat"), '$$', q{prototype() works for "Foo::Bar'concat" (compile-time)});
        ::is(concat('foo', 'bar'), 'foobar',
            'prototyped sub works with correct number of arguments (compile-time)');
    }

    ::is(prototype(\&concat), '$$', 'prototype works for \&concat');
    ::is(prototype('concat'), '$$', 'prototype works for "concat"');
    ::is(prototype('Foo::Bar::concat'), '$$', 'prototype() works for "Foo::Bar::concat"');
    ::is(prototype("Foo'Bar'concat"), '$$', q{prototype() works for "Foo'Bar'concat"});
    ::is(prototype("Foo'Bar::concat"), '$$', q{prototype() works for "Foo'Bar::concat"});
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

BEGIN { is(prototype('Foo::Bar::concat'), undef, '"Foo::Bar::concat" not prototyped in next scope (compile-time)') }
is(prototype('Foo::Bar::concat'), undef, '"Foo::Bar::concat" not prototyped in next scope (runtime)');

my $test = quotemeta $0;

is(@WARNINGS, 22, '22 diagnostic messages produced');

like(
    $WARNINGS[0],
    qr{^mysubs: creating Foo::Bar::concat \(0x0 => 0x[0-9a-z]+\) at $test line 21}, 
    'lexical sub created at line 21'
);

like(
    $WARNINGS[11],
    qr{^mysubs: deleting Foo::Bar::concat \(0x[0-9a-z]+ => 0x0\) at $test line 51}, 
    'lexical sub deleted at line 51'
);

like($WARNINGS[-2], qr{^mysubs: looking up prototype: Foo::Bar::concat at $test line 39\.},
    'last prototype check at line 39'
);

like($WARNINGS[-1], qr{^mysubs: found prototype at $test line 39\.},
    'last prototype found at line 39'
);

__END__

mysubs: creating Foo::Bar::concat (0x0 => 0x8c8f4f8) at t/prototype.t line 21
mysubs: looking up prototype: Foo::Bar::concat at t/prototype.t line 25.
mysubs: found prototype at t/prototype.t line 25.
mysubs: looking up prototype: Foo::Bar::concat at t/prototype.t line 26.
mysubs: found prototype at t/prototype.t line 26.
mysubs: looking up prototype: Foo::Bar::concat at t/prototype.t line 27.
mysubs: found prototype at t/prototype.t line 27.
mysubs: looking up prototype: Foo::Bar::concat at t/prototype.t line 28.
mysubs: found prototype at t/prototype.t line 28.
mysubs: looking up prototype: Foo::Bar::concat at t/prototype.t line 29.
mysubs: found prototype at t/prototype.t line 29.
mysubs: deleting Foo::Bar::concat (0x8c8f4f8 => 0x0) at t/prototype.t line 51
mysubs: looking up prototype: Foo::Bar::concat at t/prototype.t line 35.
mysubs: found prototype at t/prototype.t line 35.
mysubs: looking up prototype: Foo::Bar::concat at t/prototype.t line 36.
mysubs: found prototype at t/prototype.t line 36.
mysubs: looking up prototype: Foo::Bar::concat at t/prototype.t line 37.
mysubs: found prototype at t/prototype.t line 37.
mysubs: looking up prototype: Foo::Bar::concat at t/prototype.t line 38.
mysubs: found prototype at t/prototype.t line 38.
mysubs: looking up prototype: Foo::Bar::concat at t/prototype.t line 39.
mysubs: found prototype at t/prototype.t line 39.
