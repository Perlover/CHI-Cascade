package CHI::Cascade::Rule;

use strict;
use warnings;

sub new {
    my ($class, %opts) = @_;

    $opts{depends} = [ defined( $opts{depends} ) ? ( $opts{depends} ) : () ] unless ref($opts{depends}) eq 'ARRAY';
    bless { %opts, qr_params => [] }, ref($class) || $class;
}

sub qr_params {
    my $self = shift;

    if (@_) {
	$self->{qr_params} = [ @_ ];
    }
    else {
	return @{ $self->{qr_params} };
    }
}

1;
