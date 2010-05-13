#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 19;

our $AUTOLOAD;

eval { foo() };
like($@, qr{Undefined subroutine &main::foo called at }, 'foo not defined in previous scope');

eval { bar() };
like($@, qr{Undefined subroutine &main::bar called at }, 'bar not defined in previous scope');

for my $i (1 .. 2) {
    use mysubs AUTOLOAD => sub { [ $AUTOLOAD, @_ ] };

    is_deeply (foo(), [ 'main::foo' ]);
    is_deeply (foo(42), [ 'main::foo', 42 ]);

    if ($i == 1) {
        is_deeply(bar(), [ 'main::bar' ]);
        is_deeply(bar(42), [ 'main::bar', 42 ]);
    } else {
        is(bar(), 'bar!');
    }

    {
        is_deeply (foo(), [ 'main::foo' ], 'foo autoloaded in nested scope');

        if ($i == 1) {
            is_deeply(bar(), [ 'main::bar' ], 'bar autoloaded in nested scope');
            is_deeply(bar(42), [ 'main::bar', 42 ], 'bar with arguments autoloaded in nested scope');
        } else {
            is(bar(), 'bar!', 'bar still defined in nested scope');
        }
    }

    is(baz(), 'baz!');
    is(quux(), 'quux!');

    *bar = sub { "bar!" } unless (defined &bar);

    sub baz { "baz!" }

    BEGIN { *quux = sub { "quux!" } }
}

eval { foo() };
like($@, qr{Undefined subroutine &main::foo called at }, 'foo not defined in next scope');
