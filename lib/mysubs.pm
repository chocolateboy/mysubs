package mysubs;

use 5.008001;

use strict;
use warnings;

use constant {
    UNDO    => 0,
    REDO    => 1,
};

use B::Hooks::EndOfScope;
use B::Hooks::OP::Annotation;
use B::Hooks::OP::Check;
use Carp qw(croak carp);
use Devel::Pragma qw(ccstash fqname my_hints new_scope on_require);
use Scalar::Util;
use XSLoader;

our $VERSION = '1.02';
our @CARP_NOT = qw(B::Hooks::EndOfScope);

XSLoader::load(__PACKAGE__, $VERSION);

my $DEBUG = xs_get_debug(); # flag indicating whether debug messages should be printed

# The key under which the $installed hash is installed in %^H i.e. 'mysubs'
# Defined as a preprocessor macro in mysubs.xs to ensure the Perl and XS are kept in sync
my $MYSUBS = xs_sig();

# accessors for the debug flags - note there is one for Perl ($DEBUG) and one defined
# in the XS (MYSUBS_DEBUG). The accessors ensure that the two are kept in sync
sub get_debug()   { $DEBUG }
sub set_debug($)  { xs_set_debug($DEBUG = shift || 0) }
sub start_trace() { set_debug(1) }
sub stop_trace()  { set_debug(0) }

# This logs glob transitions i.e. installations and uninstallations of globs - identified
# by their IDs (see below)
sub debug ($$$$$) {
    my ($class, $action, $fqname, $old, $new) = @_; 
    my $glold = glob_id($old);
    my $glnew = glob_id($new);
    carp "$class: $action $fqname ($glold => $glnew)";
}

# The unique identifier for a typeglob - formatted as a hex value
#
# There's a bit of indirection in the GV struct that means we have to reach inside
# it to get the moral equivalent of its Scalar::Util::refaddr(). That's done in XS,
# and this sub pretty-prints it as a hex value
sub glob_id($) {
    sprintf '0x%x', xs_glob_id($_[0]);
}

# return a deep copy of the $installed hash - a hash containing the installed
# subs after any invocation of mysubs::import or mysubs::unimport
#
# the hash is cloned to ensure that inner/nested scopes don't clobber/contaminate
# outer/previous scopes with their new bindings. Likewise, unimport installs
# a new hash to ensure that previous bindings aren't clobbered e.g.
#
#   {
#       package Foo;
#
#        use mysubs bar => sub { ... };
#
#        bar();
#
#        no mysubs; # don't clobber the bindings associated with the previous subroutine call
#   }
#
# The hash and array refs are copied, but the globs are preserved.

# XXX: for some reason, Clone's clone doesn't seem to work here
sub clone($) {
    my $orig = shift;
    return { map { $_ => [ @{$orig->{$_}} ] } keys %$orig };
}

# return true if $ref ISA $class - works with non-references, unblessed references and objects
sub _isa($$) {
    my ($ref, $class) = @_;
    return Scalar::Util::blessed(ref) ? $ref->isa($class) : ref($ref) eq $class;
}

# croak with the name of this package prefixed
sub pcroak(@) {
    croak __PACKAGE__, ': ', @_;
}

# load a perl module
sub load($) {
    my $symbol = shift;
    my $module = _split($symbol)->[0];
    eval "require $module";
    pcroak "can't load $module: $@" if ($@);
}

# split "Foo::Bar::baz" into the stash (Foo::Bar) and the name (baz)
sub _split($) {
    my @split = $_[0] =~ /^(.*)::([^:]+)$/; 
    return wantarray ? @split : \@split;
}

# install a clone of the current typeglob for the supplied symbol and add a new CODE entry
# mst++ and phaylon++ for this idea
sub install_sub($$) {
    my ($symbol, $sub) = @_;
    my ($stash, $name) = _split($symbol);

    no strict 'refs';

    my $old_glob = delete ${"$stash\::"}{$name};

    # create the new glob
    *{"$stash\::$name"} = $sub;

    # copy slots over from the old glob
    if ($old_glob) {
        for my $slot (qw(SCALAR ARRAY HASH IO FORMAT)) {
            *{"$stash\::$name"} = *{$old_glob}{$slot} if (defined *{$old_glob}{$slot});
        }
    }

    return wantarray ? ($old_glob, *{"$stash\::$name"}) : *{"$stash\::$name"};
}

# restore the typeglob that existed before the lexical sub was defined - or delete it if it didn't exist
sub glob_install($$) {
    my ($symbol, $glob) = @_;
    my ($stash, $name) = _split($symbol);

    no strict 'refs';

    my $old_glob = delete ${"$stash\::"}{$name};
    ${"$stash\::"}{$name} = $glob if ($glob);

    return $old_glob;
}

# this function is used to enter or leave a lexical context, where "context" means a set of
# lexical bindings in the form of globs with or without subroutines in the CODE slot
#
# for each lexical sub, import() creates or augments a hash that stores globs in the UNDO and REDO slots.
# these globs represent the before and after state of the glob corresponding to the supplied
# (fully-qualified) sub name. The UNDO glob is the glob prior to any declaration of a lexical
# sub with that name, and the REDO glob is the currently-active glob, with the most-recently
# defined lexical sub in its CODE slot.
#
# This data is used to clean up around compile-time requires: install is called to uninstall the
# current globs (UNDO); require() is called; then install is called again to reinstall the active
# globs (REDO). this ensures lexical subs don't leak across file boundaries if the current package
# is re-opened in a required file

sub install($$) {
    my ($installed, $action_id) = @_;

    for my $fqname (keys %$installed) {
        my $action = [ 'uninstalling', 'installing' ]->[$action_id];
        my $old_glob = glob_install($fqname, $installed->{$fqname}->[$action_id]);

        debug('mysubs', $action, $fqname, $old_glob, $installed->{$fqname}->[$action_id]) if ($DEBUG);
    }
}

# install one or more lexical subs in the current scope
#
# import() has to keep track of three things:
#
# 1) $installed keeps track of *all* currently active lexical subs so that they can be
#    uninstalled before require() and reinstalled afterwards
# 2) $restore keeps track of *all* active lexical subs in the outer scope
#    so that they can be restored at the end of the current scope
# 3) $mysubs keeps track of which subs have been installed by this class (which may be a subclass of
#    mysubs) in this scope, so that they can be unimported with "no MyPragma (...)"
#
# In theory, restoration is done in two passes, the first over $installed and the second over $restore:
#
#     1) new/overridden: reinstate all the subs in $installed to their previous state in $restore (if any)
#     2) deleted: reinstate all the subs in $restore that are not defined in $installed (because
#        they were explicitly unimported)
# 
# In practice, as an optimization, an auxilliary hash ($remainder) is used to keep track of the
# elements of $restore that were removed (via unimport) from $installed. This reduces the overhead
# of the second pass so that it doesn't redundantly traverse elements covered by the first pass.

sub import {
    my ($class, %bindings) = @_;

    return unless (%bindings);

    my $autoload = delete $bindings{-autoload};
    my $debug = delete $bindings{-debug};
    my $hints = my_hints;
    my $caller = ccstash();
    my $installed;

    if (defined $debug) {
        my $old_debug = get_debug();
        if ($debug != $old_debug) {
            set_debug($debug);
            on_scope_end { set_debug($old_debug) };
        }
    }

    if (new_scope($MYSUBS)) {
        my $top_level = 0;
        my $restore = $hints->{$MYSUBS};

        if ($restore) {
            $installed = $hints->{$MYSUBS} = clone($restore); # clone
        } else {
            $top_level = 1;
            $restore = {};
            $installed = $hints->{$MYSUBS} = {}; # create

            # when a compile-time require (or do FILE) is performed, uninstall all
            # lexical subs (UNDO) and the check handler (xs_leave) beforehand,
            # and reinstate the lexical subs and check handler afterwards
            on_require(
                sub { my $hash = shift; install($hash->{$MYSUBS}, UNDO); xs_leave() },
                sub { my $hash = shift; install($hash->{$MYSUBS}, REDO); xs_enter() }
            );
            xs_enter();
        }

        # keep it around for runtime i.e. prototype()
        xs_cache($installed);

        on_scope_end {
            my $hints = my_hints; # refresh the %^H reference - doesn't work without this
            my $installed = $hints->{$MYSUBS};

            # this hash records (or will record) the lexical subs unimported from
            # the current scope
            my $remainder = { %$restore };

            for my $fqname (keys %$installed) {
                if (exists $restore->{$fqname}) {
                    unless (xs_glob_eq($installed->{$fqname}->[REDO], $restore->{$fqname}->[REDO])) {
                        $class->debug(
                            'restoring (overridden)',
                            $fqname,
                            $installed->{$fqname}->[REDO],
                            $restore->{$fqname}->[REDO]
                        ) if ($DEBUG);
                        glob_install($fqname, $restore->{$fqname}->[REDO]);
                    }
                } else {
                    $class->debug(
                        'deleting',
                        $fqname,
                        $installed->{$fqname}->[REDO],
                        $installed->{$fqname}->[UNDO]
                    ) if ($DEBUG);
                    glob_install($fqname, $installed->{$fqname}->[UNDO]);
                }

                delete $remainder->{$fqname};
            }

            for my $fqname (keys %$remainder) {
                $class->debug(
                    'restoring (unimported)',
                    $fqname,
                    $restore->{$fqname}->[UNDO],
                    $restore->{$fqname}->[REDO]
                ) if ($DEBUG);
                glob_install($fqname, $restore->{$fqname}->[REDO]);
            }
        };

        # disable mysubs altogether when we leave the top-level scope in which it was enabled
        # XXX this must be done here i.e. *after* the scope restoration handler
        # on_scope_end \&xs_leave if ($top_level);
        on_scope_end \&xs_leave if ($top_level);
    } else {
        $installed = $hints->{$MYSUBS}; # augment
    }

    # Note the class-specific data is stored under a mysubs-flavoured name rather than the
    # unadorned class name. The subclass might well have its owne uses for $^H{$class}, so we keep
    # our mitts off it
    #
    # Also, the unadorned class can't be used as a class if $MYSUBS is 'mysubs' (which
    # it is) as the two uses conflict with and clobber each other

    my $subclass = "$MYSUBS($class)";
    my $mysubs;

    # never use the $class as the identifier for new_scope() - see above
    if (new_scope($subclass)) {
        $mysubs = $hints->{$subclass};
        $mysubs = $hints->{$subclass} = $mysubs ? { %$mysubs } : {}; # clone/create
    } else {
        $mysubs = $hints->{$subclass}; # augment
    }

    for my $name (keys %bindings) {
        my $sub = $bindings{$name};

        # normalize bindings
        unless (_isa($sub, 'CODE')) {
            $sub = do {
                load($sub) if (($sub =~ s/^\+//) || $autoload);
                no strict 'refs';
                *{$sub}{CODE}
            } || pcroak "can't find subroutine: '$sub'";
        }

        my $fqname = fqname($name, $caller);
        my ($old, $new) = install_sub($fqname, $sub);

        if (exists $installed->{$fqname}) {
            $class->debug('redefining', $fqname, $old, $new) if ($DEBUG);
            $installed->{$fqname}->[REDO] = $new;
        } else {
            $class->debug('creating', $fqname, $old, $new) if ($DEBUG);
            $installed->{$fqname} = [];
            $installed->{$fqname}->[UNDO] = $old;
            $installed->{$fqname}->[REDO] = $new;
        }

        $mysubs->{$fqname} = $new;
    }
}
   
# uninstall one or more lexical subs from the current scope
sub unimport {
    my $class = shift;
    my $hints = my_hints;
    my $subclass = "$MYSUBS($class)";
    my $mysubs;

    return unless (($^H & 0x20000) && ($mysubs = $hints->{$subclass}));

    my $caller = ccstash();
    my @subs = @_ ? (map { scalar(fqname($_, $caller)) } @_) : keys(%$mysubs);
    my $installed = $hints->{$MYSUBS};
    my $new_installed = clone($installed);
    my $deleted = 0;

    for my $fqname (@subs) {
        my $glob = $mysubs->{$fqname};

        if ($glob) { # the glob this module/subclass installed
            # if the current glob ($installed->{$fqname}->[REDO]) is the glob this module installed ($mysubs->{$fqname})
            if (xs_glob_eq($glob, $installed->{$fqname}->[REDO])) {
                my $old = $installed->{$fqname}->[REDO];
                my $new = $installed->{$fqname}->[UNDO];

                $class->debug('unimporting', $fqname, $old, $new) if ($DEBUG);
                glob_install($fqname, $installed->{$fqname}->[UNDO]); # restore the glob to its pre-lexical sub state

                # what import adds, unimport taketh away
                delete $new_installed->{$fqname};
                delete $mysubs->{$fqname};

                ++$deleted;
            } else {
                carp "$class: attempt to unimport a shadowed lexical sub: $fqname";
            }
        } else {
            carp "$class: attempt to unimport an undefined lexical sub: $fqname";
        }
    }

    if ($deleted) {
        xs_cache($hints->{$MYSUBS} = $new_installed);
    }
}

1;

__END__

=head1 NAME

mysubs - lexical subroutines

=head1 SYNOPSIS

    {
        use mysubs
          foo      => sub ($) { ... },          # anonymous sub value
          bar      => \&bar,                    # code ref value
          chomp    => 'main::mychomp',          # sub name value
          dump     => '+Data::Dumper::Dumper',  # autoload Data::Dumper
         'My::foo' => \&foo,                    # package-qualified sub name
         -autoload => 1,                        # autoload all subs passed by name
         -debug    => 1                         # show diagnostic messages
        ;

        foo(...);        # OK
        prototype('foo') # '$'
        My::foo(...);    # OK
        bar;             # OK
        chomp ...;       # override builtin
        dump ...;        # override builtin
    }

    foo(...);            # compile-time error: Undefined subroutine &main::foo
    My::foo(...);        # compile-time error: Undefined subroutine &My::foo
    prototype('foo')     # undef
    chomp ...;           # builtin
    dump ...;            # builtin

=head1 DESCRIPTION

C<mysubs> is a lexically-scoped pragma that implements lexical subroutines i.e. subroutines
whose use is restricted to the lexical scope in which they are declared.

The C<use mysubs> statement takes a list of key/value pairs in which the keys are subroutine
name and the values are subroutine references or strings containing the package-qualified names
of the subroutines. In addition, C<mysubs> options may be passed.

=head1 OPTIONS

C<mysubs> options are prefixed with a hyphen to distinguish them from subroutine names.
The following options are supported:

=head2 -autoload

If the value is a package-qualified subroutine name, then the module can be automatically loaded.
This can either be done on a per-subroutine basis by prefixing the name with a C<+>, or for
all named values by supplying the C<-autoload> option with a true value e.g.

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

=head2 -debug

A trace of the module's actions can be enabled or disabled lexically by supplying the C<-debug> option
with a true or false value. The trace is printed to STDERR.

e.g.

    use mysubs
         foo   => \&foo,
         bar   => sub { ... },
        -debug => 1;

=head1 METHODS

=head2 import

C<mysubs::import> can be called indirectly via C<use mysubs> or can be overridden by subclasses to create
lexically-scoped pragmas that export subroutines whose use is restricted to the calling scope e.g.

    package MyPragma;

    use base qw(mysubs);

    sub import {
        my $class = shift;
        $class->SUPER::import(foo => sub { ... }, chomp => \&mychomp, UNIVERSAL::bar => 'My::bar');
    }

Client code can then import lexical subs from the module:

    #!/usr/bin/env perl

    {
        use MyPragma;

        foo(...);
        chomp ...;
    }

    foo(...);  # compile-time error: Undefined subroutine &main::foo
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

        foo ...;  # compile-time error: Undefined subroutine &main::foo

        no mysubs;

        bar(...); # compile-time error: Undefined subroutine &main::bar
        baz;      # compile-time error: Undefined subroutine &main::baz
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

Lexical AUTOLOAD subroutines are not currently supported.

=head1 VERSION

1.02

=head1 SEE ALSO

=over

=item * L<Sub::Lexical|Sub::Lexical>

=item * L<Method::Lexical|Method::Lexical>

=back

=head1 AUTHOR

chocolateboy <chocolate@cpan.org>, with thanks to mst (Matt S Trout), phaylon (Robert Sedlacek),
and Paul Fenwick for the idea.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2009 by chocolateboy

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
