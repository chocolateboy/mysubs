# mysubs

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [NAME](#name)
- [SYNOPSIS](#synopsis)
- [DESCRIPTION](#description)
- [OPTIONS](#options)
  - [-autoload](#-autoload)
  - [-debug](#-debug)
- [METHODS](#methods)
  - [import](#import)
  - [import_for](#import_for)
  - [unimport](#unimport)
  - [unimport_for](#unimport_for)
- [CAVEATS](#caveats)
- [VERSION](#version)
- [SEE ALSO](#see-also)
- [AUTHOR](#author)
- [COPYRIGHT AND LICENSE](#copyright-and-license)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# NAME

mysubs - lexical subroutines

# SYNOPSIS

```perl
package MyPragma;

use base qw(mysubs);

sub import {
    my $class = shift;

    $class->SUPER::import(
         foo   => sub { ... },
         chomp => \&mychomp
    );
}
```

```perl
#!/usr/bin/env perl

{
    use MyPragma;

    foo(...);
    chomp ...;
}

foo(...);  # error: Undefined subroutine &main::foo
chomp ...; # builtin
```

# DESCRIPTION

`mysubs` is a lexically-scoped pragma that implements lexical subroutines i.e. subroutines
whose use is restricted to the lexical scope in which they are imported or declared.

The `use mysubs` statement takes a list of key/value pairs in which the keys are subroutine
names and the values are subroutine references or strings containing the package-qualified names
of the subroutines. In addition, `mysubs` options may be passed.

The following example summarizes the type of keys and values that can be supplied.

```perl
{
    use mysubs
        foo      => sub ($) { ... },     # anonymous sub value
        bar      => \&bar,               # code ref value
        chomp    => 'main::mychomp',     # sub name value
        dump     => '+Data::Dump::dump', # load Data::Dump
       'My::foo' => \&foo,               # package-qualified sub name
       -autoload => 1,                   # load modules for all sub name values
       -debug    => 1                    # show diagnostic messages
    ;

    foo(...);                            # OK
    prototype('foo')                     # '$'
    My::foo(...);                        # OK
    bar;                                 # OK
    chomp ...;                           # override builtin
    dump ...;                            # override builtin
}

foo(...);                                # error: Undefined subroutine &main::foo
My::foo(...);                            # error: Undefined subroutine &My::foo
prototype('foo')                         # undef
chomp ...;                               # builtin
dump ...;                                # builtin
```

# OPTIONS

`mysubs` options are prefixed with a hyphen to distinguish them from subroutine names.
The following options are supported:

## -autoload

If the value is a package-qualified subroutine name, then the module can be automatically loaded.
This can either be done on a per-subroutine basis by prefixing the name with a `+`, or for
all named values by supplying the `-autoload` option with a true value e.g.

```perl
use mysubs
     foo      => 'MyFoo::foo',
     bar      => 'MyBar::bar',
     baz      => 'MyBaz::baz',
    -autoload => 1;
```
or

```perl
use MyFoo;
use MyBaz;

use mysubs
     foo =>  'MyFoo::foo',
     bar => '+MyBar::bar', # autoload MyBar
     baz =>  'MyBaz::baz';
```

The `-autoload` option should not be confused with lexical `AUTOLOAD` subroutines, which are also supported. e.g.

```perl
use mysubs AUTOLOAD => sub { ... };

foo(); # OK - AUTOLOAD
bar(); # ditto
baz(); # ditto
```

## -debug

A trace of the module's actions can be enabled or disabled lexically by supplying the `-debug` option
with a true or false value. The trace is printed to STDERR.

e.g.

```perl
use mysubs
     foo   => \&foo,
     bar   => sub { ... },
    -debug => 1;
```

# METHODS

## import

`mysubs::import` can be called indirectly via `use mysubs` or can be overridden by subclasses to create
lexically-scoped pragmas that export subroutines whose use is restricted to the calling scope e.g.

```perl
package MyPragma;

use base qw(mysubs);

sub import {
    my $class = shift;

    $class->SUPER::import(
         foo   => sub { ... },
         chomp => \&mychomp
    );
}
```

Client code can then import lexical subs from the module:

```perl
#!/usr/bin/env perl

{
    use MyPragma;

    foo(...);
    chomp ...;
}

foo(...);  # error: Undefined subroutine &main::foo
chomp ...; # builtin
```

The `import` method is implemented as a wrapper around `[import_for](#import_for)`.

## import\_for

`mysubs` methods are installed and uninstalled for a particular client of the `mysubs` library.
Typically, this client is identified by its class name i.e. the first argument passed
to the `[mysubs::import](#import)` method. Note: if `mysubs->import` is called implicitly (via `use mysubs ...`)
or explicitly, then the client identifier is "mysubs" i.e. `mysubs` can function as a client of itself.

The `import_for` method allows an identifier to be specified explicitly without subclassing `mysubs` e.g.

```perl
package MyPragma;

use base qw(Whatever); # we can't/don't want to subclass mysubs

use mysubs (); # don't import anything

sub import {
    my $class = shift;
    $class->SUPER::import(...); # call Whatever::import
    mysubs->import_for($class, foo => sub { ... }, ...);
}
```

The installed subs can then be uninstalled by passing the same identifier to the
`[unimport_for](#unimport_for)` method.

Note that the `import_for` identifier has nothing to do with the package the lexical subs will be
installed into. Lexical subs are always installed into the package specified in the package-qualified sub name,
or the package of the currently-compiling scope.

`mysubs->import` is implemented as a call to `mysubs->import_for` i.e.

```perl
package MyPragma;

use base qw(mysubs);

sub import {
    my $class = shift;
    $class->SUPER::import(foo => sub { ... });
}
```

\- is equivalent to:

```perl
package MyPragma;

use mysubs ();

sub import {
    my $class = shift;
    mysubs->import_for($class, foo => sub { ... });
}
```

## unimport

`mysubs::unimport` removes the specified lexical subs from the current scope, or all lexical subs
if no arguments are supplied.

```perl
use mysubs foo => \&foo;

{
    use mysubs
        bar => sub { ... },
        baz => 'Baz::baz';

    foo ...;
    bar(...);
    baz;

    no mysubs qw(foo);

    foo ...;  # error: Undefined subroutine &main::foo

    no mysubs;

    bar(...); # error: Undefined subroutine &main::bar
    baz;      # error: Undefined subroutine &main::baz
}

foo ...; # ok
```

Unimports are specific to the class supplied in the `no` statement, so pragmas that subclass
`mysubs` inherit an `unimport` method that only removes the subs they installed e.g.

```perl
{
    use MyPragma qw(foo bar baz);

    use mysubs quux => \&quux;

    foo;
    quux(...);

    no MyPragma qw(foo); # unimports foo
    no MyPragma;         # unimports bar and baz
    no mysubs;           # unimports quux
}
```

As with the `[import](#import)` method, `unimport` is implemented as a wrapper around
`[unimport_for](#unimport_for)`.

## unimport\_for

This method complements the `[import_for](#import_for)` method. i.e. it allows the identifier for a group of lexical
subs to be specified explicitly. The identifier should match the one supplied in the
corresponding `import_for` method e.g.

```perl
package MyPragma;

use mysubs ();

sub import {
    my $class = shift;
    mysubs->import_for($class, foo => sub { ... });
}

sub unimport {
    my $class = shift;
    mysubs->unimport_for($class, @_);
}
```

As with the `import_for` method, the identifier is used to refer to a group of lexical
subs, and has nothing to do with the package from which those subs will be uninstalled.
As with the import methods, the unimport methods always operate on (i.e. uninstall lexical subs from)
the package in the package-qualified sub name, or the package of the currently-compiling scope.

# CAVEATS

Lexical subs cannot be called by symbolic reference e.g.

This works:

```perl
use mysubs
    foo      => sub { ... },
    AUTOLOAD => sub { ... }
;

my $foo = \&foo;

foo();    # OK - named
bar();    # OK - AUTOLOAD
$foo->(); # OK - reference
```

This doesn't work:

```perl
use mysubs
    foo      => sub { ... },
    AUTOLOAD => sub { ... }
;

my $foo = 'foo';
my $bar = 'bar';

no strict 'refs';

&{$foo}(); # not foo
&{$bar}(); # not AUTOLOAD
```

# VERSION

1.14

# SEE ALSO

- [Sub::Lexical](https://metacpan.org/pod/Sub::Lexical)
- [Method::Lexical](https://github.com/chocolateboy/Method-Lexical)

# AUTHOR

[chocolateboy](mailto:chocolate@cpan.org), with thanks to mst (Matt S Trout), phaylon (Robert Sedlacek),
and Paul Fenwick for the idea.

# COPYRIGHT AND LICENSE

Copyright (C) 2008-2011 by chocolateboy

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
