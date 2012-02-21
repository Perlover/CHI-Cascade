package test_04;

use strict;
use Test::More;

use parent 'Exporter';
use Time::HiRes	qw(time);

our @EXPORT = qw(test_cascade);

my $recomputed;

sub test_cascade {
    my $cascade = shift;

    $cascade->rule(
	target		=> 'big_array',
	code		=> sub {
	    sleep 1;
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

    my $time1 = time;
    ok( ! defined $cascade->run( 'one_page_0', queue => 'test' ), '0th page, queued');
    my $time2 = time;

    ok( $cascade->{stats}{recompute} == 0, 'recompute stats - 2');
    ok( $time2 - $time1 < 0.1, 'time of 1st starting' );

    my $res;

    $time1 = time;
    ok ( $cascade->queue('test') == 1, '1st queue run' );
    $time2 = time;
    ok( $time2 - $time1 > 0.9 && $time2 - $time1 < 1.1, 'time of queue' );

    ok( defined( $res = $cascade->run( 'one_page_0', queue => 'test' ) ), '0th page, queued but recomputed already');
    is_deeply( $res, [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ] );

    ok ( $cascade->queue('test') == 0, 'second queue run' );

    ok( defined( $res = $cascade->run( 'one_page_1' ) ), '1th page, not queued' );
    is_deeply( $res, [ 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 ], 'result of 1st page' );

    ok( defined( $res = $cascade->run( 'one_page_1', queue => 'test' ) ), '1th page, queued' );
    is_deeply( $res, [ 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 ], 'result of 1st page' );
    ok ( $cascade->queue('test') == 0, '3rd queue run' );
}

1;
