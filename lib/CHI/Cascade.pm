package CHI::Cascade;

use strict;
use warnings;

our $VERSION = 0.17;

use Carp;

use CHI::Cascade::Value;
use CHI::Cascade::Rule;
use CHI::Cascade::Target;

sub new {
    my ($class, %opts) = @_;

    my $self = bless {
	    %opts,
	    plain_targets	=> {},
	    qr_targets		=> [],
	    target_locks	=> {},
	    stats		=> { recompute => 0 }

	}, ref($class) || $class;

    $self;
}


sub rule {
    my ($self, %opts) = @_;

    my $rule = CHI::Cascade::Rule->new( cascade => $self, %opts );

    if (ref($rule->{target}) eq 'Regexp') {
	push @{ $self->{qr_targets} }, $rule;
    }
    elsif (! ref($rule->{target})) {
	$self->{plain_targets}{$rule->{target}} = $rule;
    }
    else {
	croak qq{The rule's target "$rule->{target}" is unknown type};
    }
}

sub target_computing {
    my $trg_obj;

    ($trg_obj = $_[0]->{chi}->get("t:$_[1]"))
      ? $trg_obj->locked
      : 0;
}

sub target_time {
    my ($self, $target) = @_;

    my $trg_obj;

    return ( ($trg_obj = $self->{chi}->get("t:$target"))
      ? $trg_obj->time
      : 0
    );
}

sub get_value {
    my ($self, $target) = @_;

    $self->{chi}->get("v:$target")
      or CHI::Cascade::Value->new;
}

sub target_lock {
    my ($self, $rule) = @_;

    my ($trg_obj, $target);

    $target = $rule->target;

    $trg_obj = CHI::Cascade::Target->new unless ( ( $trg_obj = $self->{chi}->get("t:$target") ) );

    $trg_obj->lock;
    $self->{chi}->set( "t:$target", $trg_obj, $rule->{busy_lock} || $self->{busy_lock} || 'never' );

    $self->{target_locks}{$target} = 1;
}

sub target_unlock {
    my ($self, $rule, $value) = @_;

    my $target = $rule->target;

    if ( my $trg_obj = $self->{chi}->get("t:$target") ) {
	$trg_obj->unlock;
	$trg_obj->touch if $value && $value->recomputed;
	$self->{chi}->set( "t:$target", $trg_obj, 'never' );

	delete $self->{target_locks}{$target};
    }
}

sub target_remove {
    my ($self, $target) = @_;

    $self->{chi}->remove("t:$target");
}

sub touch {
    my ($self, $target) = @_;

    if ( my $trg_obj = $self->{chi}->get("t:$target") ) {
	$trg_obj->touch;
	$self->{chi}->set( "t:$target", $trg_obj, 'never' );
    }
}

sub target_locked {
    exists $_[0]->{target_locks}{$_[1]};
}

sub recompute {
    my ( $self, $rule, $target, $dep_values) = @_;

    my $ret = eval { $rule->{code}->( $rule, $target, $rule->{dep_values} = $dep_values ) };

    $self->{stats}{recompute}++;

    if ($@) {
	my $error = $@;
	die( (eval { $error->isa('CHI::Cascade::Value') }) ? $error : "CHI::Cascade: the target $target - error in the code: $error" );
    }

    my $value;

    $self->{chi}->set( "v:$target", $value = CHI::Cascade::Value->new->value($ret), 'never' );
    $rule->{recomputed}->( $rule, $target, $value ) if ( ref $rule->{recomputed} eq 'CODE' );
    return $value->recomputed(1);
}

sub value_ref_if_recomputed {
    my ( $self, $rule, $target, $only_from_cache ) = @_;

    return undef unless defined $rule;

    my @qr_params = $rule->qr_params;

    $self->{chain}{$target} = 1;

    if ( $self->target_computing($target) ) {
	# If we have any target as a being computed (dependencie/original)
	# there is no need to compute anything - trying to return original target value
	die $self->get_value($self->{orig_target});
    }

    my ( %dep_values, $dep_name );

    if ( $only_from_cache ) {

	# Trying to get value from cache
	my $value = $self->get_value($target);

	return $value if $value->is_value;

	# If no in cache - we should recompute it again
	$self->target_lock($rule);
    }

    my $ret = eval {
	my $dep_target;

	foreach my $depend (@{ $rule->depends }) {
	    $dep_target = ref($depend) eq 'CODE' ? $depend->( $rule, @qr_params ) : $depend;

	    $dep_values{$dep_target}->[0] = $self->find($dep_target);

	    die qq{Found a circled rule (target '$dep_target' as dependence of '$target')"}
	      if ( ! $only_from_cache && exists $self->{chain}{$dep_target} );

	    $self->target_lock($rule)
	      if (   ! $only_from_cache
		  && ( ( $dep_values{$dep_target}->[1] = $self->value_ref_if_recomputed( $dep_values{$dep_target}->[0], $dep_target ) )->recomputed
		  || ( $self->target_time($dep_target) > $self->target_time($target) ) ) );
	}

	$self->target_lock($rule) if ! $self->target_time($target);

	if ( $self->target_locked($target) ) {
	    # We should recompute this target
	    # So we should recompute values for other dependencies
	    foreach $dep_target (keys %dep_values) {
		if ( ! $dep_values{$dep_target}->[1]->is_value ) {
		    if ( ! ( $dep_values{$dep_target}->[1] = $self->value_ref_if_recomputed( $dep_values{$dep_target}->[0], $dep_target, 1 ) )->is_value ) {
			warn "assertion: value of dependence '$dep_target' should be in cache but none there";
			$self->target_remove($dep_target);
			return undef;
		    }
		}
	    }
	}

	return $self->recompute( $rule, $target, { map { $_ => $dep_values{$_}->[1]->value } keys %dep_values } )
	  if $self->target_locked($target);

	return undef;
    };

    my $e = $@;
    $self->target_unlock($rule, $ret)
      if $self->target_locked($target);
    die $e if $e;

    return $ret || CHI::Cascade::Value->new;
}

sub run {
    my ($self, $target) = @_;

    croak qq{The target ($target) for run should be string} if ref($target);
    croak qq{The target for run is empty} if $target eq '';

    $self->{chain} = {};

    my $ret = eval {
	$self->{orig_target} = $target;

	my $value = $self->value_ref_if_recomputed( $self->find($target), $target );

	if ( ! $value->is_value ) {
	    $value = $self->get_value( $target );
	    if ( ! $value->is_value ) {
		$self->target_remove($target);
		warn "assertion: value for target '$target' should be in cache but none there";
	    }
	}
	return $value;
    };

    if ($@) {
	$ret = $@;
	die $ret unless eval { $ret->isa('CHI::Cascade::Value') };
    }

    return $ret->value;
}

sub find {
    my ($self, $plain_target) = @_;

    die "CHI::Cascade::find : got empty target\n" if $plain_target eq '';

    my $new_rule;

    # If target is flat text
    if (exists $self->{plain_targets}{$plain_target}) {
	( $new_rule = $self->{plain_targets}{$plain_target}->new )->{matched_target} = $plain_target;
	return $new_rule;
    }

    # If rule's target is Regexp type
    foreach my $rule (@{$self->{qr_targets}}) {
	my @qr_params;

	if (@qr_params = $plain_target =~ $rule->{target}) {
	    ( $new_rule = $rule->new )->qr_params(@qr_params);
	    $new_rule->{matched_target} = $plain_target;
	    return $new_rule;
	}
    }

    die "CHI::Cascade::find : cannot find the target $plain_target\n";
}


1;
__END__

=pod

=head1 NAME

CHI::Cascade - a cache dependencies (cache and like 'make' utility concept)

=head1 SYNOPSIS

    use CHI;
    use CHI::Cascade;

    $cascade = CHI::Cascade->new(chi => CHI->new(...));

    $cascade->rule(
	target	=> 'unique_name',
	depends	=> ['unique_name_other1', 'unique_name_other2'],
	code	=> sub {
	    my ($rule, $target_name, $values_of_depends) = @_;

	    # $values_of_depends == {
	    #     unique_name_other1 => $value_1,
	    #     unique_name_other2 => $value_2
	    # }
	    # $rule->target	eq	$target_name
	    # $rule->depends	===	['unique_name_other1', 'unique_name_other2']
	    # $rule->dep_values	==	$values_of_depends
	    # $rule->params	==	{ a => 1, b => 2 }

	    # Now we can calcualte $value
	    return $value;
	},
	params	=> { a => 1, b => 2 }
    );

    $cascade->rule(
	target	=> 'unique_name_other1',
	depends	=> 'unique_name_other3',
	code	=> sub {
	    my ($rule, $target_name, $values_of_depends) = @_;

	    # $values_of_depends == {
	    #     unique_name_other3 => $value_3
	    # }

	    # computing here
	    return $value;
	}
    );

    $value_of_this_target = $cascade->run('unique_name');

=head1 DESCRIPTION

This module is the attempt to use a benefits of caching and 'make' concept.
If we have many an expensive tasks and want to cache it we can split its
to small expsnsive tasks and to describe dependencies for cache items.

This module is experimental yet. I plan to improve it near time but some things
already work. You can take a look for t/* tests as examples.

=head1 CONSTRUCTOR

$cascade = CHI::Cascade->new( %options )

This method constructs a new C<CHI::Cascade> object and returns it.
Key/value pair arguments may be provided to set up the initial state.
Options are:

=over

=item chi

Required. Instance of L<CHI> object. The L<CHI::Cascade> doesn't construct this
object for you. Please create instance of C<CHI> yourself.

=item busy_lock

Optional. Default is I<never>. I<This is not C<busy_lock> option of CHI!> This
is amount of time (to see L<CHI/"DURATION EXPRESSIONS">) until all target locks
expire. When a target is recomputed it is locked. If process is to be
recomputing target and it will die or OS will be hangs up we can dead locks and
locked target will never recomputed again. This option helps to avoid it. You
can set up a special busy_lock for rules too.

=back

=head1 METHODS

=over

=item rule( %options )

To add new rule to C<CHI::Cascade> object. All rules should be added before
first L</run> method

The keys of %options are:

=over

=item target

B<Required.> A target for L</run> and for searching of L</depends>. It can be as
scalar text or C<Regexp> object created through C<qr//>

=item depends

B<Optional.> The B<scalar>, B<arrayref> or B<coderef> values of dependencies.
This is the definition of target(s) from which this current rule is dependent.
If I<depends> is:

=over

=item scalar

It should be plain text of single dependence of this target.

=item arrayref

An each item of list can be scalar value (exactly matched target) or code
reference. If item is coderef it will be executed as $coderef->( $rule,
L<$rule-E<gt>qr_params|CHI::Cascade::Rule/qr_params> ) and should return a
scalar value as current dependence for this target at runtime (the API for
coderef parameters was changed since v0.16)

=item coderef

This subroutine will be executed every time inside I<run> method if necessary
and with parameters as: $coderef->( $rule,
L<$rule-E<gt>qr_params|CHI::Cascade::Rule/qr_params> ) (API was changed since
v0.16). It should return B<scalar> or B<arrayref>. The returned value is
I<scalar> it will be considered as single dependence of this target and the
behavior will be exactly as described for I<scalar> in this paragraph. If the
returned value is I<arrayref> it will be considered as list of dependencies for
this target and the behavior will be exactly as described for I<arrayref> in
this paragraph.

=back

=item code

B<Required.> The code reference for computing a value of this target. Will be
executed if no value in cache for this target or any dependence or dependences
of dependences and so on will be recomputed. Will be executed as $code->( $rule,
$target, $hashref_to_value_of_dependencies ) I<(The API of running this code was
changed since v0.10)>

=over

=item $rule

An instance of L<CHI::Cascade::Rule> object. You can use it object as accessor
for some current executed target data (plain text of target, for getting of
parameters and so on). Please to see L<CHI::Cascade::Rule>

=item $target

A current target as plain text (what a target the $cascade got from L<run>
method)

=item $hashref_to_value_of_dependencies

A hash reference of values of all dependencies for current target. Keys in this
hash are flat strings of dependecies and values are computed or cached ones.

This module should guarantee that values of dependencies will be valid values
even if value is C<undef>. This code can return C<undef> value as a valid code
return but author doesn't recommend it. If C<CHI::Cascade> could not get a valid
values of all dependencies of current target before execution of this code the
last will not be executed (The C<run> will return C<undef>).

=back

=item params

You can pass in your code any additional parameters by this option. These
parameters are accessed in your code through L<params|CHI::Cascade::Rule/params>
method of L<CHI::Cascade::Rule> instance object.

=item busy_lock

Optional. Default is L</busy_lock> of constructor or I<never> if first is not
defined. I<This is not C<busy_lock> option of CHI!> This is amount of time (to
see L<CHI/"DURATION EXPRESSIONS">) until target lock expires. When a target is
recomputed it is locked. If process is to be recomputing target and it will die
or OS will be hangs up we can dead locks and locked target will never recomputed
again. This option helps to avoid it.

=item recomputed

Optional. This is a recomputed callback (coderef). If target of this rule was
recomputed this callback will be executed right away after recomputed value has
been saved in cache. The callback will be executed as $coderef->( $rule,
$target, $value ) where are:

=over

=item $rule

An instance of L<CHI::Cascade::Rule> class. This instance is recreated for every
target searching and recomputing if need.

=item $target

A current target as string

=item $value

The instance of L<CHI::Cascade::Value> class. You can use a recomputed value as
$value->value

=back

For example you can use this callback for notifying of other sites that your
target's value has been changed and is already in cache.

=back

=item run( $target )

This method makes a cascade computing if need and returns value for this target
If any dependence of this target of any dependencies of dependencies were
recomputed this target will be recomputed too.

=item touch( $target )

This method refreshes the time of this target. Here is analogy with L<touch>
utility of Unix and behaviour as L<make> after it. After L</touch> all targets
are dependent from this target will be recomputed at next L</run> with an
appropriate ones.

=item target_remove ( $target )

It's like a removing of target file in make. You can force to recompute target
by this method. It will remove target marker if one exists and once when cascade
will need target value it will be recomputed. In a during recomputing of course
cascade will return an old value if one exists in cache.

=back

=head1 STATUS

This module is experimental and not finished for new features ;-)
Please send me issues through L<https://github.com/Perlover/CHI-Cascade> page

=head1 ANALOGIES WITH make

Here simple example how it works. Here is a direct analogy to Unix make
utility:

    In CHI::Cascade:		In make:

    rule			rule
    depends			prerequisites
    code			commands
    run( rule_name )		make target_name

=head1 FEATURES

The features of this module are following:

=over

=item Computing inside process

If module needs to compute item for cache we compute inside process (no forks)
For web applications it means that one process for one request could take
a some time for computing. But other processes will not wait and will get either
old previous computed value or I<undef> value.

=item Non-blocking computing for concurrent processes

If other process want to get data from cache we should not block it. So
concurrent process can get an old data if new computing is run or can get
I<undef> value. A concurrent process should decide itself what it should do
after it - try again after few time or print some message like 'Please wait and
try again' to user.

=item Each target is splitted is two items in cache

For optimization this module keeps target's info by separately from value item.
A target item has lock & timestamp fields. A value item has a computed value.

=back

=head1 EXAMPLE

For example please to see the SYNOPSIS

When we prepared a rules and a depends we can:

If unique_name_other1 and/or unique_name_other2 are(is) more newer than
unique_name the unique_name will be recomputed.
If in this example unique_name_other1 and unique_name_other2 are older than
unique_name but the unique_name_other3 is newer than unique_name_other1 then
unique_name_other1 will be recomputed and after the unique_name will be
recomputed.

And even we can have a same rule:

    $cascade->rule(
	target	=> qr/^unique_name_(.*)$/,
	depends	=> sub { 'unique_name_other_' . $_[1] },
	code	=> sub {
	    my ($rule, $target_name, $values_of_depends) = @_;

	    # $rule->qr_params		=== ( 3 )
	    # $target_name		== 'unique_name_3' if $cascade->run('unique_name_3') was
	    # $values_of_depends	== {
	    #     unique_name_other_3	=> $value_ref_3
	    # }
	}
    );

    $cascade->rule(
	target	=> qr/unique_name_other_(.*)/,
	code	=> sub {
	    my ($rule, $target_name, $values_of_depends) = @_;
	    ...
	}
    );

When we will do:

    $cascade->run('unique_name_52');

$cascade will find rule with qr/^unique_name_(.*)$/, will make =~ and will find
a depend as unique_name_other_52

=head1 AUTHOR

This module has been written by Perlover <perlover@perlover.com>

=head1 LICENSE

This module is free software and is published under the same terms as Perl
itself.

=head1 SEE ALSO

=over

=item L<CHI::Cascade::Rule>

An instance of this object can be used in your target codes.

=item L<CHI>

This object is used for cache.

=item L<CHI::Driver::Memcached::Fast>

Recommended if you have the Memcached

=item L<CHI::Driver::File>

Recommended if you want to use the file caching instead the Memcached for
example

=back

=cut
