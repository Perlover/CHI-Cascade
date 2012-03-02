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

1;
