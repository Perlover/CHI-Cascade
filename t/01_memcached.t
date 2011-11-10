use strict;
use Test::More;

use CHI;
use CHI::Cascade;

plan skip_all => 'Not installed CHI::Driver::Memcached::Fast'
  unless eval "use CHI::Driver::Memcached::Fast; 1";

my $cwd;
chomp($cwd = `pwd`);

my $out = `memcached -d -s $cwd/t/memcached.socket -a 644 -m 64 -c 10 -P $cwd/t/memcached.pid -t 2 2>&1`;

if ($?) {
    chomp $out;
    plan skip_all => "Cannot start the memcached for this test ($out)";
}
else {
    plan tests => 14;
}

$SIG{__DIE__} = sub {
    `{ kill cat t/memcached.pid; rm -f t/memcached.pid; rm -f t/memcached.socket; } >/dev/null 2>&1`;
};

my $cascade = CHI::Cascade->new(
    chi => CHI->new(
	driver		=> 'Memcached::Fast',
	servers		=> ['t/memcached.socket'],
	namespace	=> 'CHI::Cascade::tests'
    )
);

isa_ok( $cascade, 'CHI::Cascade');

$cascade->rule(
    target		=> 'big_array',
    code		=> sub {
	return [ 1 .. 1000 ];
    }
);

$cascade->rule(
    target		=> qr/^one_page_(\d+)$/,
    depends		=> 'big_array',
    code		=> sub {
	my ($target, $values) = @_;

	my ($page) = $target =~ /^one_page_(\d+)$/;

	my $ret = [ @{$values->{big_array}}[ ($page * 10) .. (( $page + 1 ) * 10 - 1) ] ];
	$ret;
    }
);

ok( $cascade->{stats}{recompute} == 0, 'recompute stats');

is_deeply( $cascade->run('one_page_0'), [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ], '0th page from cache');
ok( $cascade->{stats}{recompute} == 2, 'recompute stats');

is_deeply( $cascade->run('one_page_1'), [ 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 ], '1th page from cache');
ok( $cascade->{stats}{recompute} == 3, 'recompute stats');

is_deeply( $cascade->run('one_page_0'), [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ], '0th page from cache');
ok( $cascade->{stats}{recompute} == 3, 'recompute stats');

# To force recalculate dependencied
$cascade->touch('big_array');

is_deeply( $cascade->run('one_page_0'), [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ], '0th page from cache after touching');
ok( $cascade->{stats}{recompute} == 4, 'recompute stats');

is_deeply( $cascade->run('one_page_1'), [ 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 ], '1th page from cache after touching');
ok( $cascade->{stats}{recompute} == 5, 'recompute stats');

is_deeply( $cascade->run('one_page_0'), [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ], '0th page from cache');
ok( $cascade->{stats}{recompute} == 5, 'recompute stats');

$SIG{__DIE__}->();
