package mysubs;

use 5.008;

use strict;
use warnings;

use Carp qw(croak);
use Scope::Guard;
use Scalar::Util;
use Devel::Hints::Lexical qw(my_hints);
use XSLoader;

our $VERSION = '0.01';

XSLoader::load __PACKAGE__, $VERSION;

# return true if $ref ISA $class - works with non-references, unblessed references and objects
sub _isa($$) {
    my ($ref, $class) = @_;
    return Scalar::Util::blessed(ref) ? $ref->isa($class) : ref($ref) eq $class;
}

# croak with the name of this package prefixed
sub _pcroak(@) {
    croak __PACKAGE__, ': ', @_;
}

# load a module
sub _load($) {
    my $symbol = shift;
    my $module = _split($symbol)->[0];
    eval "require $module";
    _pcroak "can't load $module: $@" if ($@);
}

# split "Foo::Bar::baz" into the stash (Foo::Bar) and the name (baz)
sub _split($) {
    my @split = $_[0] =~ /^(.*)::([^:]+)$/; 
    return wantarray ? @split : \@split;
}

# install a clone of the current typeglob for the supplied symbol and add a new CODE entry
# mst++ via phaylon++ for this idea
sub glob_enter($$) {
    my ($symbol, $sub) = @_;
    my ($stash, $name) = _split($symbol);

    no strict 'refs';

    my $old_glob = exists(${"$stash\::"}{$name}) ? delete ${"$stash\::"}{$name} : undef;

    # create the new glob
    *{"$stash\::$name"} = $sub || \&dummy; # assign a dummy to suppress warnings

    # but delete the CODE slot if $sub is undef
    delete_sub($symbol) unless ($sub);

    # copy slots over from the old glob
    if ($old_glob) {
	for my $slot (qw(SCALAR ARRAY HASH IO FORMAT)) {
	    *{"$stash\::$name"} = *{$old_glob}{$slot} if (defined *{$old_glob}{$slot});
	}
    }

    return $old_glob;
}

# restore the previous typeglob
sub glob_leave($$) {
    my ($symbol, $glob) = @_;
    my ($stash, $name) = _split($symbol);

    no strict 'refs';

    delete ${"$stash\::"}{$name};
    ${"$stash\::"}{$name} = $glob if ($glob);
}

# install lexical subs
sub import {
    my ($class, %bindings) = @_;
    my $caller = caller;

    return unless (%bindings);

    # normalize bindings
    for my $name (keys %bindings) {
	my $sub = $bindings{$name};

        unless (_isa($sub, 'CODE')) {
	    $sub = do {
		_load($sub) if ($sub =~ s/^\+//);
		no strict 'refs';
		*{$sub}{CODE}
	    } || _pcroak "can't find subroutine: '$name'";
	}

	$bindings{$name} = glob_enter("$caller\::$name", $sub);
    }

    my $bindings = { %bindings };

    my $guard = Scope::Guard->new(
	sub {
	    for my $name (keys %$bindings) {
		my $old_glob = $bindings->{$name};
		glob_leave("$caller\::$name", $old_glob);
	    }
	}
    );

    my_hints->{$guard} = $guard;
}

1;

__END__

=head1 NAME

mysubs - lexical subroutines

=head1 SYNOPSIS

    {
        use mysubs
            foo   => sub { print "foo", $/ },
            bar   => \&bar,
            dump  => '+Data::Dumper::dump', # autoload Data::Dumper
            chomp => 'main::mychomp';

        foo(...);
        bar;
	dump ...;
        chomp ...; # override builtin
    }

    foo(...);   # runtime error: Undefined subroutine &main::foo
    chomp ...;  # builtin

=head1 DESCRIPTION

C<mysubs> is a lexically-scoped pragma that implements lexical subroutines i.e. subroutines whose definition
is restricted to the lexical scope in which they are visible.

The C<use mysubs> statement takes a list of key/value pairs in which the keys are local subroutine names
and the values are subroutine references or strings containing the package name of the
subroutine.

If the value is a name that begins with a "+", then the package is autoloaded e.g.

    use mysubs ref => '+UNIVERSAL::ref::ref'; # autoload UNIVERSAL::ref

=head1 CAVEATS

=over

=item * Lexical subs currently leak into compile-time C<require>s (e.g. via C<use>)
of files that re-open the calling package.

e.g.

    # main.pl

    package MyPackage;

    use MyPackage::Extra;

    use my subs foo => sub { ... };

    # MyPackage/Extra.pm

    package MyPackage;

    sub extra {
	foo( ... ); # shouldn't work, but does
    }
	
=item * Lexical methods are not currently implemented e.g.

    package Foo;

    use mysubs bar => sub { ... };

    sub new { ... }

    my $object = __PACKAGE__->new();

    $object->bar(); # doesn't work

=back

=head1 VERSION

0.01

=head1 SEE ALSO

=over

=item * L<Subs::Lexical|Subs::Lexical>

=back

=head1 AUTHOR

chocolateboy <chocolate.boy@email.com>, with thanks to phaylon (Robert Sedlacek) and
mst (Matt S Trout) for inspiration.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by chocolateboy

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
