package CHI::Cascade::Target;

use strict;
use warnings;

use Time::HiRes;

sub new {
    my ($class, %opts) = @_;

    bless { %opts }, ref($class) || $class;
}

sub lock {
    $_[0]->{locked} = $$;
}

sub locked {
    exists $_[0]->{locked}
      and $_[0]->{locked};
}

sub unlock {
    delete $_[0]->{locked};
}

sub time {
    $_[0]->{time} || 0;
}

sub touch {
    $_[0]->{time} = Time::HiRes::time;
}

sub actual_stamp {
    $_[0]->{actual_stamp} = Time::HiRes::time;
}

sub is_actual {
    ( $_[0]->{actual_stamp} || $_[0]->{time} || 0 ) + $_[1] >= Time::HiRes::time;
}

sub ttl {
    my $self = shift;

    if (@_) {
	$self->{finish_time} = Time::HiRes::time + $_[0];
	return $self;
    }
    else {
	return $self->{finish_time} ? $self->{finish_time} - Time::HiRes::time : undef;
    }
}

1;
