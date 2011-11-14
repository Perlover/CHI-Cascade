package CHI::Cascade::Value;

use strict;
use warnings;

# value = undef				-> no in cache
use constant CASCADE_NO_CACHE		=> 1 << 0;

# value = undef | old_value		-> other process is computing this target or any dependence
use constant CASCADE_COMPUTING		=> 1 << 1;

# value = old_value | actual_value	-> the value from cache (not computed now)
use constant CASCADE_FROM_CACHE		=> 1 << 2;

# value = actual_value			-> this value is actual
use constant CASCADE_ACTUAL_VALUE	=> 1 << 3;

# value = actual_value & recomuted now	-> this value is computed right now
use constant CASCADE_COMPUTED_NOW	=> 1 << 4;

# value = undef | old_value		-> a computing temporarily unavailable
use constant CASCADE_COMPUTING_T_U	=> 1 << 5;

use parent 'Exporter';

{
    no strict 'refs';

    our %EXPORT_TAGS = (
	bits		=> [ map { "&$_" } grep { /^CASCADE_$/ && *{$_}{CODE} } keys %{ __PACKAGE__ . "::" } ]
    );
    Exporter::export_ok_tags( keys %EXPORT_TAGS );
}

sub new {
    my ($class, %opts) = @_;

    bless { %opts }, ref($class) || $class;
}

sub is_value {
    shift->{is_value};
}

sub bits {
    if (@_) {
	$_[0]->{bits} |= $_[1];
	return $self;
    }
    $self->{bits};
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
