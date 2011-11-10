use strict;
use warnings;

use inc::Module::Install;

name 'CHI-Cascade';
all_from 'lib/CHI/Cascade.pm';

abstract 'Cache dependencies (principles of operation of make utility)';
author 'Perlover <perlover@perlover.com>';

requires 'CHI';

WriteAll();
