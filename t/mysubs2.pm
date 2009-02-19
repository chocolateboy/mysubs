package mysubs2;

use strict;
use warnings;

use base qw(mysubs1);

sub import { shift->SUPER::import(@_) }

1;
