package CHI::Cascade::Rule;

use strict;
use warnings;

use Scalar::Util 'weaken';

sub new {
    my ($class, %opts) = @_;

    my $from = ref($class) ? $class : \%opts;

    $opts{depends} = [ defined( $opts{depends} ) ? ( $opts{depends} ) : () ] unless ref( $opts{depends} );

    # To do clone or new object
    my $self = bless {
	map( { $_ => $from->{$_} }
	  grep { exists $from->{$_} }
	  qw( target depends depends_catch code params busy_lock cascade recomputed actual_term )),
	qr_params	=> [],
	matched_target	=> undef
    }, ref($class) || $class;

    weaken $self->{cascade};	# It is against memory leaks

    $self;
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

sub depends {
    my $self = shift;

    if ( ref( $self->{depends} ) eq 'CODE' ) {
	my $res = $self->{depends}->( $self, $self->qr_params );

	return ref($res) eq 'ARRAY' ? $res : [ $res ];
    }

    return $self->{depends};
}

sub value_expires {
    my $self = shift;

    if (@_) {
	$self->{value_expires} = $_[0];
	return $self;
    }
    $self->{value_expires} || 'never';
}


sub target	{ shift->{matched_target}	}
sub params	{ shift->{params}		}
sub cascade	{ shift->{cascade}		}
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

	    # An execution of $cascade->run('target_12') will pass in code a $rule as:
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

An instance of this object is created by L<CHI::Cascade> in L<CHI::Cascade/rule>.

=head1 DESCRIPTION

The instance of this object is passed to L<CHI::Cascade/code>,
L<CHI::Cascade/coderef>, L<CHI::Cascade/recomputed>,
L<CHI::Cascade/depends_catch> by L<CHI::Cascade> as first argument I<(The API of
running this code was changed since v0.16)>. You can use it object as accessor
to some parameters of your currect executed target.

=head1 METHODS

=over

=item qr_params

returns a list. It is used for getting a result of C<=~> operation if target is
described for L<rule|CHI::Cascade/rule> through C<qr//> operator.

=item depends

returns arrayref of dependencies (L<depends|CHI::Cascade/depends> option of
L<rule|CHI::Cascade/rule> method) even if one scalar value is passed there (as
one dependence). Always is defined even there no defined C<depends> option for
C<rule>. If L<'depends'|CHI::Cascade/depends> is coderef you will get a returned
value of one.

=item target

returns current target as plain text after matching.

=item params

returns any data of any type what were passed to L<CHI::Cascade/params>

=item cascade

returns reference to L<CHI::Cascade> instance object for this rule.

=back

=head1 AUTHOR

This module has been written by Perlover <perlover@perlover.com>

=head1 LICENSE

This module is free software and is published under the same terms as Perl
itself.

=head1 SEE ALSO

L<CHI::Cascade>

=cut
