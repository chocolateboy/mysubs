#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 16;

my $error = qr{^Undefined subroutine &main::test called at};

ok(not(defined &test), 'not defined in previous scope');

{
    use mysubs test => sub {
        my $name = shift;
        unlike($name, qr{^redefine}, $name);
    };

    test 'scope';
    test('scope with parens');

    {
        BEGIN {
            test 'nested scope';
            test('nested scope with parens');
        }

        use mysubs foo => sub {
            pass(shift);
        };

        use mysubs test => sub {
            my $name = shift;
            like($name, qr{^redefine}, $name);
        };

        foo 'nested sub';
        foo('nested sub with parens');

        test 'redefine';
        test('redefine with parens');

        use mysubs 'Foo::Bar::baz' => sub { pass('fully-qualified name works') };
        Foo::Bar::baz;
    }

    ok(not(defined &concat), "prototyped sub doesn't leak into an outer scope");
    ok(not(defined &Foo::Bar::baz), "fully-qualified name doesn't leak into an outer scope");

    test 'scope again';
    test('scope again with parens');
    eval q{pass("string eval")};
}

ok(not(defined &test), 'not defined in next scope');
