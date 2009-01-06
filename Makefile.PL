use 5.008;

use ExtUtils::MakeMaker;
use Config;

my $optimize;

if ($Config{gccversion}) {
    $optimize = '-O3 -Wall';
} elsif ($Config{osname} eq 'MSWin32') {
    $optimize = '-O2 -W4';
} else {
    $optimize = $Config{optimize};
}

WriteMakefile(
    NAME          => 'mysubs',
    VERSION_FROM  => 'lib/mysubs.pm',
    PREREQ_PM     => {
        'Devel::Pragma'        => '0.31',
        'B::Hooks::EndOfScope' => '0.05',
    },
    ABSTRACT_FROM => 'lib/mysubs.pm',
    AUTHOR        => 'chocolateboy <chocolate.boy@email.com>',
    LIBS          => [''],
    DEFINE        => '',
    INC           => '-I.',
    OPTIMIZE      => $optimize,
    ($ExtUtils::MakeMaker::VERSION >= 6.31 ? (LICENSE => 'perl') : ()),
);
