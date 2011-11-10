package CHI::Cascade::Target;

use strict;
use warnings;

use Time::HiRes;

sub new {
    my ($class, %opts) = @_;

    bless { %opts }, ref($class) || $class;
}

sub lock {
    shift->{locked} = $$;
}

sub locked {
    exists $_[0]->{locked}
      and $_[0]->{locked};
}

sub unlock {
    delete shift->{locked};
}

sub time {
    shift->{time};
}

sub touch {
    shift->{time} = Time::HiRes::time;
}

1;
