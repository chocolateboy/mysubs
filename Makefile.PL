use 5.008001;

use strict;
use warnings;

use ExtUtils::MakeMaker;
use ExtUtils::Depends;
use Config;

our $OPTIMIZE;

if ($Config{gccversion}) {
    $OPTIMIZE = '-O3 -Wall -W';
    $OPTIMIZE .= ' -g -Wextra -Wdeclaration-after-statement' if (-d 'dev');
} elsif ($Config{osname} eq 'MSWin32') {
    $OPTIMIZE = '-O2 -W4';
} else {
    $OPTIMIZE = $Config{optimize};
}

our %XS_PREREQUISITES = (
    'B::Hooks::OP::Annotation' => '0.43',
    'B::Hooks::OP::Check'      => '0.18',
);

our %XS_DEPENDENCIES = ExtUtils::Depends->new('mysubs', keys(%XS_PREREQUISITES))->get_makefile_vars();

WriteMakefile(
    NAME          => 'mysubs',
    VERSION_FROM  => 'lib/mysubs.pm',
    PREREQ_PM => {
        'B::Hooks::EndOfScope' => '0.09',
        'Devel::Pragma'        => '0.54',
        %XS_PREREQUISITES
    },
    ABSTRACT_FROM => 'lib/mysubs.pm',
    AUTHOR        => 'chocolateboy <chocolate@cpan.org>',
    LIBS          => [''],
    DEFINE        => '',
    INC           => '-I.',
    OPTIMIZE      => $OPTIMIZE,
    (eval($ExtUtils::MakeMaker::VERSION) >= '6.46' ?
        (META_MERGE => {
            configure_requires => {
                'ExtUtils::Depends' => '0.304',
                %XS_PREREQUISITES
            },
            resources => {
                repository => 'http://github.com/chocolateboy/mysubs'
            },
        })
        : ()
    ),
    (eval($ExtUtils::MakeMaker::VERSION) >= '6.31' ? (LICENSE => 'perl') : ()),
    %XS_DEPENDENCIES,
);
