use strict;
use warnings;

use inc::Module::Install;

name 'CHI-Cascade';
abstract 'A cache dependencies (principles of operation of make utility)';

author 'Perlover <perlover@perlover.com>';
version_from 'lib/CHI/Cascade.pm';
auto_set_repository;
license 'perl';

requires 'CHI';
requires 'Time::HiRes';

build_requires 'Test::More';
build_requires 'Test::Base';

WriteAll();

package MY;

sub distdir {
    my $inherited = shift->SUPER::distdir(@_);
    $inherited =~ s/^(create_distdir\s.*)/$& README/m;
    $inherited .= "README : lib/CHI/Cascade.pm\n\tperldoc -t lib/CHI/Cascade.pm > README\n";
    return $inherited;
}
