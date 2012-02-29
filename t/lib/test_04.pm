package test_04;

use strict;
use Test::More;

use parent 'Exporter';
use Time::HiRes	qw(time);

our @EXPORT = qw(test_cascade);

my $recomputed;

sub test_cascade {
    my $cascade = shift;

    plan tests => 22;

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

    ok( $cascade->{stats}{recompute} == 0 );

    my $state;

    my $time1 = time;
    ok( ! defined $cascade->run( 'one_page_0', queue => 'test', state => \$state ) );
    my $time2 = time;

    ok( $cascade->{stats}{recompute} == 0 );
    ok( $time2 - $time1 < 0.1 );
    ok( CHI::Cascade::Value->state_as_str($state) eq "CASCADE_NO_CACHE | CASCADE_QUEUED" );

    my $res;

    $time1 = time;
    ok ( $cascade->queue('test') == 1 );
    $time2 = time;
    ok( $time2 - $time1 > 0.9 && $time2 - $time1 < 1.1 );

    ok( defined( $res = $cascade->run( 'one_page_0', queue => 'test', state => \$state ) ) );
    is_deeply( $res, [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ] );
    ok( CHI::Cascade::Value->state_as_str($state) eq "CASCADE_ACTUAL_VALUE | CASCADE_FROM_CACHE" );

    ok ( $cascade->queue('test') == 0 );

    ok( defined( $res = $cascade->run( 'one_page_1', state => \$state ) ) );
    is_deeply( $res, [ 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 ] );
    ok( CHI::Cascade::Value->state_as_str($state) eq "CASCADE_ACTUAL_VALUE | CASCADE_RECOMPUTED" );

    ok( defined( $res = $cascade->run( 'one_page_1', queue => 'test', state => \$state ) ) );
    is_deeply( $res, [ 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 ] );
    ok( CHI::Cascade::Value->state_as_str($state) eq "CASCADE_ACTUAL_VALUE | CASCADE_FROM_CACHE" );
    ok ( $cascade->queue('test') == 0 );

    $cascade->target_remove( 'one_page_1' );

    ok( defined( $res = $cascade->run( 'one_page_1', queue => 'test', state => \$state ) ) );
    is_deeply( $res, [ 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 ] );
    ok( CHI::Cascade::Value->state_as_str($state) eq "CASCADE_FROM_CACHE | CASCADE_QUEUED" );
    ok ( $cascade->queue('test') == 1 );
}

1;
