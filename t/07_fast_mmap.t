use strict;

use lib 't/lib';
use test_04;

use Test::More;

use CHI;
use CHI::Cascade;

plan skip_all => "Not installed CHI::Driver::FastMmap ($@)"
  unless eval "use CHI::Driver::FastMmap; 1";

plan tests => 22;

$SIG{__DIE__} = sub {
    `{ rm -rf t/fast_mmap; } >/dev/null 2>&1`;
    $SIG{__DIE__} = 'IGNORE';
};

`{ rm -rf t/fast_mmap; } >/dev/null 2>&1`;

my $cascade = CHI::Cascade->new(
    chi => CHI->new(
	driver		=> 'FastMmap',
	root_dir	=> 't/fast_mmap'
    )
);

test_cascade($cascade);

$SIG{__DIE__} eq 'IGNORE' || $SIG{__DIE__}->();
