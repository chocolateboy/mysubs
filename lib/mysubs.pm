package mysubs;

use 5.008;

use strict;
use warnings;

use Carp qw(croak);
use B::Hooks::EndOfScope;
use Scalar::Util;
use Devel::Pragma qw(new_scope ccstash my_hints);
use XSLoader;

our $VERSION = '0.20';

my %CACHE;

XSLoader::load(__PACKAGE__, $VERSION);

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
# mst++ and phaylon++ for this idea
sub glob_enter($$) {
    my ($symbol, $sub) = @_;
    my ($stash, $name) = _split($symbol);

    no strict 'refs';

    my $old_glob = exists(${"$stash\::"}{$name}) ? delete ${"$stash\::"}{$name} : undef;

    # create the new glob
    *{"$stash\::$name"} = $sub;

    # copy slots over from the old glob
    if ($old_glob) {
        for my $slot (qw(SCALAR ARRAY HASH IO FORMAT)) {
            *{"$stash\::$name"} = *{$old_glob}{$slot} if (defined *{$old_glob}{$slot});
        }
    }

    return $old_glob;
}

# restore the previous typeglob - or delete it if it didn't exist
sub glob_leave($$) {
    my ($symbol, $glob) = @_;
    my ($stash, $name) = _split($symbol);

    no strict 'refs';

    delete ${"$stash\::"}{$name};
    ${"$stash\::"}{$name} = $glob if ($glob);
}

# clear lexical subs before require()
sub require_enter($) {
    my $bindings = shift;
    for my $key (keys %$bindings) {
        glob_leave($key, $bindings->{$key}->[0]);
    }
}

# restore lexical subs after require()
sub require_leave($) {
    my $bindings = shift;
    for my $key (keys %$bindings) {
        glob_enter($key, $bindings->{$key}->[1]);
    }
}

# install lexical subs
sub import {
    my ($class, %bindings) = @_;

    return unless (%bindings);
    my (undef, $filenamex, $linex) = caller;

    my $debug = delete $bindings{-debug};
    my $autoload = delete $bindings{-autoload};
    my $caller = ccstash();
    my $hints = my_hints;
    my $new_scope = new_scope($class);
    my ($mysubs, %restore);
   
    if ($new_scope) {
        # clone the bindings so that definitions in a nested scope don't contaminate
        # those in an outer scope
        $mysubs = $hints->{$class} ? { %{ $hints->{$class} } } : {};

        # make sure this hash stays alive till runtime for require()
        $CACHE{$mysubs} = $mysubs;

        # create a snapshot of the current lexical sub bindings (if any) in effect at
        # the beginning of the scope
        # this is restored by a B::Hooks::EndOfScope hook at the
        # end of the (compilation of the) current scope
        for my $fqname (keys %$mysubs) {
            no strict 'refs';
            $restore{$fqname} = *{$fqname};
        }
    } else {
        $mysubs = $hints->{$class};
    }

    my (undef, $filename, $line) = caller;

    # normalize bindings
    for my $name (keys %bindings) {
        my $sub = $bindings{$name};

        unless (_isa($sub, 'CODE')) {
            $sub = do {
                _load($sub) if (($sub =~ s/^\+//) || $autoload);
                no strict 'refs';
                *{$sub}{CODE}
            } || _pcroak "can't find subroutine: '$sub'";
        }

        my $fqname = "$caller\::$name";

        if (exists $mysubs->{$fqname}) {
            print STDERR "$class: redefining $fqname ($filename:$line)", $/
                if $debug;
            glob_enter($fqname, $sub);
            $mysubs->{$fqname}->[1] = $sub;
        } else {
            print STDERR "$class: creating $fqname ($filename:$line)", $/
                if $debug;
            $mysubs->{$fqname}->[0] = glob_enter($fqname, $sub);
            $mysubs->{$fqname}->[1] = $sub;
        }
    }

    if ($new_scope) {
        $hints->{$class} = $mysubs;

        on_scope_end {
            my (undef, $filename, $line) = caller(1);

            for my $fqname (keys %$mysubs) {
                if (exists $restore{$fqname}) {
                    print STDERR "$class: restoring $fqname ($filename:$line)", $/
                        if $debug;
                    glob_leave($fqname, $restore{$fqname});
                } else {
                    print STDERR "$class: deleting $fqname ($filename:$line)", $/
                        if $debug;
                    glob_leave($fqname, $mysubs->{$fqname}->[0]);
                }
            }

            _leave();
        };

        _enter();
    }
}

# uninstall one or more lexical subs from the current scope
sub unimport {
    my $class = shift;

    return unless (($^H & 0x20000) && $^H{$class});

    my $mysubs = $^H{$class};
    my $caller = ccstash();
    my @subs = @_ ? (map { "$caller\::$_" } @_) : keys(%$mysubs);

    for my $fqname (@subs) {
        if ($mysubs->{$fqname}) {
            glob_leave($fqname, $mysubs->{$fqname}->[0]);
        } else {
            _pcroak("can't remove lexical sub '$fqname': not defined"); 
        }
    }
}

1;

__END__

=head1 NAME

mysubs - lexical subroutines

=head1 SYNOPSIS

    {
        use mysubs
             foo       => sub { print "foo", $/ }, # anonymous sub
             bar       => \&bar,                   # code ref
             chomp     => 'main::mychomp',         # sub name
             dump      => '+Data::Dumper::Dumper', # autoload Data::Dumper
            -autoload  => 1,                       # autoload all subs passed by name
            -debug     => 1;                       # show diagnostic messages

        foo(...);
        bar;
        dump ...;  # override builtin
        chomp ...; # override builtin
    }

    foo(...);  # runtime error: Undefined subroutine &main::foo
    chomp ...; # builtin

=head1 DESCRIPTION

C<mysubs> is a lexically-scoped pragma that implements lexical subroutines i.e. subroutines whose use
is restricted to the lexical scope in which they are defined.

The C<use mysubs> statement takes a list of key/value pairs in which the keys are C<mysubs> options or local
subroutine names and the values are subroutine references or strings containing the package name of the
subroutine.

=head1 OPTIONS

Options can be passed to the C<use mysubs> statement. They are prefixed with a C<-> to distinguish them from
local subroutine names. The following options are supported:

=head2 autoload

If the sub is a package-qualified subroutine name, then the module can be automatically loaded.
This can either be done on a per-subroutine basis by prefixing the name with a C<+>, or for
all name arguments by supplying the C<-autoload> option with a true value e.g.

    use mysubs
         foo      => 'MyFoo::foo',
         bar      => 'MyBar::bar',
         baz      => 'MyBaz::baz',
        -autoload => 1;
or

    use MyFoo;
    use MyBaz;

    use mysubs
         foo =>  'MyFoo::foo',
         bar => '+MyBar::bar', # autoload MyBar
         baz =>  'MyBaz::baz';

=head2 debug

If the C<-debug> option is supplied with a true value, a trace of the module's actions is printed to STDERR.

e.g.

    use mysubs
         foo   => \&foo,
         bar   => sub { ... },
        -debug => 1;

=head1 METHODS

=head2 import

C<mysub::import> can be called indirectly via C<use mysubs> or can be overridden to create
lexically-scoped pragmas that export subroutines whose use is limited to the calling scope e.g.

    package MyPragma;

    use base qw(mysubs);

    sub import {
        my $class = shift;
        $class->SUPER::import(foo => sub { ... }, chomp => \&mychomp, ...);
    }

Client code can then import lexical subs from the module:

    #!/usr/bin/env perl

    {
        use MyPragma;

        foo(...);
        chomp ...;
    }

    foo(...);  # runtime error: Undefined subroutine &main::foo
    chomp ...; # builtin

=head2 unimport

C<mysubs::unimport> removes the specified lexical subs from the current scope, or all lexical subs 
if no arguments are supplied.

    use mysubs foo => \&foo;

    {
        use mysubs
            bar => sub { ... },
            baz => 'Baz::baz';

        foo ...;
        bar(...);
        baz;

        no mysubs qw(foo);

        foo ...;  # runtime error: Undefined subroutine &main::foo

        no mysubs;

        bar(...); # runtime error: Undefined subroutine &main::bar
        baz;      # runtime error: Undefined subroutine &main::baz
    }

    foo ...; # ok

Unimports are specific to the class supplied in the C<no> statement, so pragmas that subclass
C<mysubs> inherit an C<unimport> method that only removes the subs they installed e.g.

    {
        use MyPragma qw(foo bar baz);

        use mysubs quux => \&quux;

        foo;
        quux(...);

        no MyPragma qw(foo); # unimports foo
        no MyPragma;         # unimports bar and baz

        no mysubs;           # unimports quux
    }

=head1 CAVEATS

=over

=item * Lexical (i.e. private) methods are not currently implemented e.g.

    package Foo;

    use mysubs bar => sub { ... };

    sub new { ... }

    my $self = __PACKAGE__->new();

    $self->bar(); # doesn't work

=back

=head1 VERSION

0.20

=head1 SEE ALSO

=over

=item * L<Subs::Lexical|Subs::Lexical>

=item * L<Devel::Pragma|Devel::Pragma>

=back

=head1 AUTHOR

chocolateboy <chocolate.boy@email.com>, with thanks to phaylon (Robert Sedlacek),
mst (Matt S Trout) and Paul Fenwick for the idea.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2009 by chocolateboy

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
