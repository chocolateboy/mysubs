package test_4;

use base qw(mysubs);

sub import { shift->SUPER::import(test1 => sub { Test::More::pass('child') }) }

1;
