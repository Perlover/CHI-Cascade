use strict;
use Test::More;

use CHI;
use CHI::Cascade;

use IO::Handle;
use Storable	qw(store_fd fd_retrieve);
use Time::HiRes	qw(sleep time);

use constant DELAY	=> 2.0;

plan skip_all => 'Not installed CHI::Driver::Memcached::Fast'
  unless eval "use CHI::Driver::Memcached::Fast; 1";

my $cwd;
chomp($cwd = `pwd`);

my $out = `memcached -d -s $cwd/t/memcached.socket -a 644 -m 64 -c 10 -P $cwd/t/memcached.pid -t 2 2>&1`;

if ($?) {
    chomp $out;
    plan skip_all => "Cannot start the memcached for this test ($out)";
}

my ($pid_slow, $pid_quick);

setup_for_slow_process();

if ($pid_slow = fork) {
    setup_slow_parent();
}
else {
    die "cannot fork: $!" unless defined $pid_slow;
    setup_slow_child();
    run_slow_process();
}

setup_for_quick_process();

if ($pid_quick = fork) {
    setup_quick_parent();
}
else {
    die "cannot fork: $!" unless defined $pid_quick;
    setup_quick_child();
    run_quick_process();
}

# Here parent - it will command

$SIG{__DIE__} = sub {
    `{ kill \`cat t/memcached.pid\`; rm -f t/memcached.pid; rm -f t/memcached.socket; } >/dev/null 2>&1`;
    kill 15, $pid_slow if $pid_slow;
    kill 15, $pid_quick if $pid_quick;
    waitpid($pid_slow, 0);
    waitpid($pid_quick, 0);
    $SIG{__DIE__} = 'IGNORE';
};

$SIG{TERM} = $SIG{INT} = $SIG{HUP} = sub { die "Terminated by " . shift };
$SIG{ALRM} = sub { die "Alarmed!" };

alarm( DELAY * 2 + 2 );

start_parent_commanding();

exit 0;

sub start_parent_commanding {
    plan tests => 5;

    my $in;

    print CHILD_SLOW_WTR "save1\n"		or die $!;

    sleep 0.1;

    print CHILD_QUICK_WTR "read1\n"		or die $!;
    $in = fd_retrieve(\*CHILD_QUICK_RDR)	or die "fd_retrieve";

    ok( $in->{time2} - $in->{time1} < 0.1, 'time of read1' );
    ok( ! defined($in->{value}), 'value of read1' );

    $in = fd_retrieve(\*CHILD_SLOW_RDR);

    ok(	abs( DELAY * 2 - $in->{time2} + $in->{time1} ) < 0.1, 'time of save1' );
    ok(	defined($in->{value}), 'value of save1 defined' );
    is_deeply( $in->{value}, [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ], 'value of save1' );

    print CHILD_SLOW_WTR "exit\n"		or die $!;
    print CHILD_QUICK_WTR "exit\n"		or die $!;

    $SIG{__DIE__}->();
}

sub run_slow_process {
    my $line;

    my $cascade = CHI::Cascade->new(
	chi => CHI->new(
	    driver		=> 'Memcached::Fast',
	    servers		=> ['t/memcached.socket'],
	    namespace		=> 'CHI::Cascade::tests'
	)
    );

    set_cascade_rules($cascade, DELAY);

    my $out;

    while ($line = <PARENT_SLOW_RDR>) {
	chomp $line;

	if ($line eq 'save1') {
	    $out = {};

	    $out->{time1} = time;
	    $out->{value} = $cascade->run('one_page_0');
	    $out->{time2} = time;
	    store_fd $out, \*PARENT_SLOW_WTR;
	}
	elsif ($line eq 'exit') {
	    exit 0;
	}
    }
}

sub run_quick_process {
    my $line;

    my $cascade = CHI::Cascade->new(
	chi => CHI->new(
	    driver		=> 'Memcached::Fast',
	    servers		=> ['t/memcached.socket'],
	    namespace		=> 'CHI::Cascade::tests'
	)
    );

    set_cascade_rules($cascade, 0);

    my $out;

    while ($line = <PARENT_QUICK_RDR>) {
	chomp $line;

	if ($line eq 'read1') {
	    $out = {};

	    $out->{time1} = time;
	    $out->{value} = $cascade->run('one_page_0');
	    $out->{time2} = time;
	    store_fd $out, \*PARENT_QUICK_WTR;
	}
	elsif ($line eq 'exit') {
	    exit 0;
	}
    }
}



sub setup_for_slow_process {
    pipe(PARENT_SLOW_RDR, CHILD_SLOW_WTR);
    pipe(CHILD_SLOW_RDR,  PARENT_SLOW_WTR);
    CHILD_SLOW_WTR->autoflush(1);
    PARENT_SLOW_WTR->autoflush(1);
}

sub setup_for_quick_process {
    pipe(PARENT_QUICK_RDR, CHILD_QUICK_WTR);
    pipe(CHILD_QUICK_RDR,  PARENT_QUICK_WTR);
    CHILD_QUICK_WTR->autoflush(1);
    PARENT_QUICK_WTR->autoflush(1);
}

sub setup_slow_parent {
    close PARENT_SLOW_RDR; close PARENT_SLOW_WTR;
}

sub setup_quick_parent {
    close PARENT_QUICK_RDR; close PARENT_QUICK_WTR;
}

sub setup_slow_child {
    close CHILD_SLOW_RDR; close CHILD_SLOW_WTR;
}

sub setup_quick_child {
    close CHILD_QUICK_RDR; close CHILD_QUICK_WTR;
}

sub set_cascade_rules {
    my ($cascade, $delay) = @_;

    $cascade->rule(
	target		=> 'big_array',
	code		=> sub {
	    sleep $delay;
	    return [ 1 .. 1000 ];
	}
    );

    $cascade->rule(
	target		=> qr/^one_page_(\d+)$/,
	depends		=> 'big_array',
	code		=> sub {
	    my ($target, $values) = @_;

	    my ($page) = $target =~ /^one_page_(\d+)$/;

	    sleep $delay;
	    my $ret = [ @{$values->{big_array}}[ ($page * 10) .. (( $page + 1 ) * 10 - 1) ] ];
	    $ret;
	}
    );
}
