package CHI::Cascade::Value;

use strict;
use warnings;

my %states = (
    # value = undef			-> no in cache
    CASCADE_NO_CACHE			=> 1 << 0,

    # value = undef | old_value		-> other process is computing this target or its any dependencies
    CASCADE_COMPUTING			=> 1 << 1,

    # value = undef | old_value		-> there was forking for recomputing
    CASCADE_FORKED			=> 1 << 2,

    # value = old_value | actual_value	-> the value from cache (not computed now)
    CASCADE_FROM_CACHE			=> 1 << 3,

    # value = actual_value		-> this value is actual
    CASCADE_ACTUAL_VALUE		=> 1 << 4,

    # value = actual_value & recomuted now	-> this value is recomputed right now
    CASCADE_RECOMPUTED			=> 1 << 5,

    # value = undef | old_value | value passed by exception -> code of target or code of any dependencies has raised an exception
    CASCADE_CODE_EXCEPTION		=> 1 << 6
);

for ( keys %states ) {
    no strict 'refs';
    no warnings 'redefine';

    my $bit = $states{$_};

    *{ $_ } = sub () { $bit }
}


use parent 'Exporter';

{
    no strict 'refs';

    our %EXPORT_TAGS = (
	state		=> [ map { "$_" } grep { /^CASCADE_/ && *{$_}{CODE} } keys %{ __PACKAGE__ . "::" } ]
    );
    Exporter::export_ok_tags( keys %EXPORT_TAGS );
}

sub new {
    my ($class, %opts) = @_;

    my $self = bless { %opts }, ref($class) || $class;

    $self->{state} ||= 0;

    $self;
}

sub is_value {
    shift->{is_value};
}

sub state {
    my $self = shift;

    if (@_) {
	$self->{state} |= $_[0];
	return $self;
    }
    $self->{state};
}

sub state_as_str {
    my $state = $_[1];

    return '' if ! $state;

    my @names;

    for ( keys %states ) {
	push @names, $_
	  if ( $state & $states{$_} );
    }

    join( " | ", sort @names );
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

sub thrown_from_code {
    my $self = shift;

    if (@_) {
	$self->{thrown_from_code} = $_[0];
	return $self;
    }
    $self->{thrown_from_code};
}

1;

__END__

=head1 NAME

CHI::Cascade::Value - a class for valid values

=head1 SYNOPSIS

You can use it class for a returning of values by exceptions. For example:

    die CHI::Cascade::Value->new

This throws an exception with nothing value. If you do it from your recompute
code your L<CHI::Cascade/run> method will return an old value from cache or if
it's not in cache it will return an C<undef> value.

Or

    die CHI::Cascade::Value->new->value( $any_value );
    die CHI::Cascade::Value->new->value( undef );

This throws an exception with valid value. Please note that C<undef> is valid
value too! But bacause the L<CHI::Cascade/run> method returns only a value (not
instance of L<CHI::Cascade::Value> object) there is not recommended to use
C<undef> values (C<run> method returns C<undef> when it cannot get a value right
now).

Please use it class only in special cases - when you need to break recopmuting,
want to return an specific value only for once execution of L<CHI::Cascade/run>
method and don't want to save value in cache.

=head1 CONSTRUCTOR

    $value = CHI::Cascade::Value->new;

It will create instance $value with nothing value

=head1 METHODS

=over

=item value

Examples:

    $value->value
    $value->value( $new_value )

You can use it to get/set a value of $value. An C<undef> value is valid too!
First version returns a value, second sets a value and returns C<$value>.

=item is_value

    $value->is_value

returns C<true> if value was set by L</value> method or C<false> else.

=back

=head1 AUTHOR

This module has been written by Perlover <perlover@perlover.com>

=head1 LICENSE

This module is free software and is published under the same terms as Perl
itself.

=head1 SEE ALSO

L<CHI::Cascade>

=cut
