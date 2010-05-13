#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 3;

sub foo { 'outer' }

is foo(), 'outer', 'pre: outer sub';

{
    use mysubs foo => sub { 'inner' };

    is foo(), 'inner', 'shadow sub';
}

is foo(), 'outer', 'post: outer sub';
