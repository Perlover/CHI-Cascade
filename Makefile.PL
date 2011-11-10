use strict;
use warnings;

use inc::Module::Install;

name 'CHI-Cascade';

version_from 'lib/CHI/Cascade.pm';
license 'perl';

abstract 'Cache dependencies (principles of operation of make utility)';
author 'Perlover <perlover@perlover.com>';

requires 'CHI';

WriteAll();
