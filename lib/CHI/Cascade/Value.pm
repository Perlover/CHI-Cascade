package CHI::Cascade::Value;

use strict;
use warnings;

sub new {
    my ($class, %opts) = @_;

    bless { %opts }, ref($class) || $class;
}

sub is_value {
    shift->{is_value};
}

sub recomputed {
    my $self = shift;

    if (@_) {
	$self->{recomputed} = $_[0];
	return $self;
    }
    $self->{recomputed};
}

sub value {
    my $self = shift;

    if (@_) {
	$self->{is_value} = 1;
	$self->{value} = $_[0];
	return $self;
    }
    $self->{value};
}

1;
