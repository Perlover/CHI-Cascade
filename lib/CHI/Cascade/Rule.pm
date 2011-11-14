package CHI::Cascade::Rule;

use strict;
use warnings;

sub new {
    my ($class, %opts) = @_;

    my $from = ref($class) ? $class : \%opts;

    $opts{depends} = [ defined( $opts{depends} ) ? ( $opts{depends} ) : () ] unless ref($opts{depends}) eq 'ARRAY';

    # To do clone or new object
    bless {
	map({ $_ => $from->{$_}}
	  grep { exists $from->{$_} }
	  qw( target depends code params busy_lock )),
	qr_params	=> [],
	matched_target	=> undef
    }, ref($class) || $class;
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

sub depends	{ shift->{depends}		}
sub target	{ shift->{matched_target}	}
sub params	{ shift->{params}		}
sub dep_values	{ shift->{dep_values}		}

1;
__END__

=head1 NAME

CHI::Cascade::Rule - a rule class

=head1 SYNOPSIS

    $cascade->rule(
	target	=> qr/^target_(\d+)$/,
	depends	=> 'base_target',
	code	=> sub {
	    my ( $rule, $target, $dep_values ) = @_;

	    # For executino of $cascade->run('target_12') will be:
	    #
	    # $rule->target	eq	$target
	    # $rule->depends	===	[ 'base_target' ]
	    # $rule->qr_params	===	( 12 )
	    # $rule->params	==	[ 1, 2, 3 ]
	},
	params	=> [ 1, 2, 3 ]
    );

    $cascade->run('target_12');

=head1 CONSTRUCTOR

An instance of this object is created by L<CHI::Cascade> in L<rule
method|CHI::Cascade/rule>.

=head1 DESCRIPTION

The instance of this object is passed to L<your code|CHI::Cascade/code> by
L<CHI::Cascade> as first argument I<(The API of running this code was changed
since v0.10)> You can use it object as accessor to some parameters of your
currect executed target.

=head1 METHODS

=over

=item qr_params

returns a list. Is used for getting a result of C<=~> operation if target is
described for L<rule|CHI::Cascade/rule> through C<qr//> operator.

=item depends

returns arrayref of dependencies (L<depends|CHI::Cascade/depends> option of
L<rule|CHI::Cascade/rule> method) even if one scalar value is passed there (as
one dependence). Always is defined even there no defined C<depends> option for
C<rule>.

=item target

returns current target as plain text after matching.

=item params

returns any data of any type what were passed to L<params|CHI::Cascade/params>

=back

=head1 AUTHOR

This module has been written by Perlover <perlover@perlover.com>

=head1 LICENSE

This module is free software and is published under the same terms as Perl
itself.

=head1 SEE ALSO

L<CHI::Cascade>

=cut
