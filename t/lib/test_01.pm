package test_01;

use strict;
use Test::More;
use CHI::Cascade::Value ':state';

use parent 'Exporter';

our @EXPORT = qw(test_cascade);

my $recomputed;

sub test_cascade {
    my $cascade = shift;

    isa_ok( $cascade, 'CHI::Cascade');

    $cascade->rule(
	target		=> 'big_array',
	code		=> sub {
	    return [ 1 .. 1000 ];
	},
	recomputed	=> sub { $recomputed++ }
    );

    $cascade->rule(
	target		=> qr/^one_page_(\d+)$/,
	depends		=> 'big_array',
	code		=> sub {
	    my ($rule) = @_;

	    my ($page) = $rule->target =~ /^one_page_(\d+)$/;

	    my $ret = [ @{$rule->dep_values->{big_array}}[ ($page * 10) .. (( $page + 1 ) * 10 - 1) ] ];
	    $ret;
	},
	recomputed	=> sub { $recomputed++ }
    );

    ok( $cascade->{stats}{recompute} == 0, 'recompute stats - 1');

    is_deeply( $cascade->run('one_page_0'), [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ], '0th page from cache');
    ok( $cascade->{stats}{recompute} == 2 && $recomputed == 2, 'recompute stats - 2');

    is_deeply( $cascade->run('one_page_1'), [ 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 ], '1th page from cache');
    ok( $cascade->{stats}{recompute} == 3, 'recompute stats - 3');

    is_deeply( $cascade->run('one_page_0'), [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ], '0th page from cache');
    ok( $cascade->{stats}{recompute} == 3, 'recompute stats - 4');

    sleep 1;

    # To force recalculate dependencied
    $cascade->touch('big_array');

    is_deeply( $cascade->run('one_page_0'), [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ], '0th page from cache after touching');
    cmp_ok( $cascade->{stats}{recompute}, '==', 4, 'recompute stats - 5');

    is_deeply( $cascade->run('one_page_1'), [ 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 ], '1th page from cache after touching');
    cmp_ok( $cascade->{stats}{recompute}, '==', 5, 'recompute stats - 6');

    is_deeply( $cascade->run('one_page_0'), [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ], '0th page from cache');
    cmp_ok( $cascade->{stats}{recompute}, '==', 5, 'recompute stats - 7');

    ok( $cascade->{stats}{recompute} == $recomputed, 'recompute stats - 8');

    # To checking of actual_term option
    $cascade->touch('big_array');

    my $state = 0;

    is_deeply( $cascade->run( 'one_page_0', state => \$state, actual_term => 2.0 ), [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ], '0th page from cache after touching');
    ok( $cascade->{stats}{recompute} == 5, 'recompute stats - 9');
    ok( $state & CASCADE_ACTUAL_TERM, 'recompute stats - 10' );

    is_deeply( $cascade->run('one_page_1', state => \$state, actual_term => 2.0), [ 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 ], '1th page from cache after touching');
    ok( $cascade->{stats}{recompute} == 5, 'recompute stats - 11');
    ok( $state & CASCADE_ACTUAL_TERM, 'recompute stats - 12' );

    select( undef, undef, undef, 2.2 );

    is_deeply( $cascade->run( 'one_page_0', state => \$state, actual_term => 2.0 ), [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ], '0th page from cache after touching');
    ok( $cascade->{stats}{recompute} == 6, 'recompute stats - 13');
    ok( ! ( $state & CASCADE_ACTUAL_TERM ), 'recompute stats - 14' );
}

1;
