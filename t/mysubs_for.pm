package mysubs_for;

use strict;
use warnings;

use mysubs ();

sub import {
    my $class = shift;
    mysubs->import_for('foo bar', foo => sub () { 'foo' }, bar => sub () { 'bar' });
}

sub unimport {
    my $class = shift;
    mysubs->unimport_for('foo bar', @_);
}

1;
