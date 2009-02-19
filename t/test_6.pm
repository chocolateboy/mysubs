package test_6;

use base qw(test_5);

sub import { shift->SUPER::import(test2 => sub { Test::More::pass('grandchild') }) }

1;
