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
__END__

=head1 NAME

CHI::Cascade::Rule - a rule class

=head1 SYNOPSIS

    $arrayref	= $rule->{depends}	# Always defined and is an arrayref
    $target	= $rule->{target}	# A $scalar or Regexp reference
    $coderef	= $rule->{code}		# The coderef of target
    $params	= $rule->{params}	# parameters passed to L<CHI::Cascade/rule> method

=head1 DESCRIPTION

Don't use it directly. Instances of this class are only created by CHI::Cascade
through L<CHI::Cascade/rule> method.

You can use it only in your code of target (since 0.06 version) accessed through
third parameter ( $third_parameter->{rule} )

=head1 SEE ALSO

L<CHI::Cascade>

=cut

