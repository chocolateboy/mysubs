#!/usr/bin/env perl

use strict;
use warnings;

use if (-d 't'), lib => 't';

use File::Spec;
use Test::More tests => 18;

{
    use mysubs2 test => sub { pass(shift) };

    BEGIN {
        require test_1;
    }

    test('previous: require');

    ok(test1(), "previous: lexical subs don't leak into packages re-opened via require");

    {
        test('nested: require');
        ok(test1(), "nested: lexical subs don't leak into packages re-opened via require");
    }

    test('next: require');
    ok(test1(), "next: lexical subs don't leak into packages re-opened via require");
}

{
    use mysubs2 test => sub { pass(shift) };
    use test_2;

    test('previous: use');
    ok(test2(), "previous: lexical subs don't leak into packages re-opened via use");

    {
        test('nested: use');
        ok(test2(), "nested: lexical subs don't leak into packages re-opened via use");
    }

    test('next: use');
    ok(test2(), "next: lexical subs don't leak into packages re-opened via use");
}

{
    use mysubs2 test => sub { pass(shift) };

    BEGIN {
        my $file = (-d 't') ? File::Spec->catfile('t', 'test_3.pm') : 'test_3.pm';
        do $file;
    }

    test('previous: do FILE');
    ok(test3(), "previous: lexical subs don't leak into packages re-opened via do FILE");

    {
        test('nested: do FILE');
        ok(test3(), "nested: lexical subs don't leak into packages re-opened via do FILE");
    }

    test('next: do FILE');
    ok(test3(), "next: lexical subs don't leak into packages re-opened via do FILE");
}
