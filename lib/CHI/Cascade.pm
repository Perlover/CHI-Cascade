package CHI::Cascade;

use strict;
use warnings;

our $VERSION = 0.04;

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

    my $rule = CHI::Cascade::Rule->new( %opts );

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
    my ($self, $target) = @_;

    my $trg_obj;

    $trg_obj = CHI::Cascade::Target->new unless ( ( $trg_obj = $self->{chi}->get("t:$target") ) );

    $trg_obj->lock;
    $self->{chi}->set("t:$target", $trg_obj);

    $self->{target_locks}{$target} = 1;
}

sub target_unlock {
    my ($self, $target, $value) = @_;

    if ( my $trg_obj = $self->{chi}->get("t:$target") ) {
	$trg_obj->unlock;
	$trg_obj->touch if $value->recomputed;
	$self->{chi}->set("t:$target", $trg_obj);

	delete $self->{target_locks}{$target};
    }
}

sub touch {
    my ($self, $target) = @_;

    if ( my $trg_obj = $self->{chi}->get("t:$target") ) {
	$trg_obj->touch;
	$self->{chi}->set("t:$target", $trg_obj);
    }
}

sub target_locked {
    exists $_[0]->{target_locks}{$_[1]};
}

sub recompute {
    my ( $self, $rule, $target, $dep_values) = @_;

    my $ret = eval { $rule->{code}->($target, $dep_values) };

    $self->{stats}{recompute}++;

    if ($@) {
	die "CHI::Cascade: the target $target - error in the code: $@";
    }

    my $value;

    $self->{chi}->set("v:$target", $value = CHI::Cascade::Value->new->value($ret));
    $value->recomputed(1);
}

sub value_ref_if_recomputed {
    my ( $self, $rule, $target, $only_from_cache ) = @_;

    my $qr_params = $rule->qr_params;

    $self->{chain}{$target} = 1;

    return undef unless $rule;

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
	$self->target_lock($target);
    }

    my $ret = eval {
	my $dep_target;

	foreach my $depend (@{ $rule->{depends} }) {
	    $dep_target = ref($depend) eq 'CODE' ? $depend->($qr_params) : $depend;

	    die qq{Found a circled target "$dep_target"}
	      if ! $only_from_cache && exists $self->{chain}{$dep_target};

	    $dep_values{$dep_target}->[0] = $self->find($dep_target);

	    $self->target_lock($target)
	      if (   ! $only_from_cache
		  && ( ( $dep_values{$dep_target}->[1] = $self->value_ref_if_recomputed( $dep_values{$dep_target}->[0], $dep_target ) )->recomputed
		  || ( $self->target_time($dep_target) > $self->target_time($target) ) ) );
	}

	$self->target_lock($target) if ! $self->target_time($target);

	if ( $self->target_locked($target) ) {
	    # We should recompute this target
	    # So we should recompute values for other dependencies
	    foreach $dep_target (keys %dep_values) {
		if ( ! $dep_values{$dep_target}->[1]->is_value ) {
		    return undef
		      unless ( $dep_values{$dep_target}->[1] = $self->value_ref_if_recomputed( $dep_values{$dep_target}->[0], $dep_target, 1 ) )->is_value;
		}
	    }
	}

	return $self->recompute( $rule, $target, { map { $_ => $dep_values{$_}->[1]->value } keys %dep_values } )
	  if $self->target_locked($target);

	return undef;
    };

    my $e = $@;
    $self->target_unlock($target, $ret)
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

	return $self->get_value( $target ) unless ($value->is_value);
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
    # If target is flat text
    return $self->{plain_targets}{$plain_target} if (exists $self->{plain_targets}{$plain_target});

    # If rule's target is Regexp type
    foreach my $rule (@{$self->{qr_targets}}) {
	my @qr_params;

	if (@qr_params = $plain_target =~ $rule->{target}) {
	    $rule->qr_params(@qr_params);
	    $rule->{matched_target} = $plain_target;
	    return $rule;
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
	    my ($target_name, $values_of_depends) = @_;

	    # $values_of_depends == {
	    #     unique_name_other1 => $value_1,
	    #     unique_name_other2 => $value_2
	    # }

	    # Now we can calcualte $value
	    return $value;
	}
    );

    $cascade->rule(
	target	=> 'unique_name_other1',
	depends	=> 'unique_name_other3',
	code	=> sub {
	    my ($target_name, $values_of_depends) = @_;

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

=over

=item $cascade = CHI::Cascade->new( %options )

This method constructs a new C<CHI::Cascade> object and returns it.
Key/value pair arguments may be provided to set up the initial state.
Now there is only one option: I<chi> - instance of L<CHI> object.

=back

=head1 METHODS

=over

=item rule( %options )

To add new rule to C<CHI::Cascade> object. All rules should be added before first
L</run> method

The keys of %options are:

=over

=item target

A target for L</run> and for searching of L</depends>. It can be as scalar text
or C<Regexp> object created through C<qr//>

=item depends

The list or a scalar value of dependencies - the list of targets which
the current rule is dependent. Each item can be scalar value (exactly matched
target) or code reference which will be executed during matching of target.
A code subroutine will get a parameters from C<=~> operator against C<target>
matching by C<qr//> operator(not tested while) - please see the section
L</EXAMPLE> for this example.

=item code

The code reference for computing a value of this target. Will be executed if no
value in cache for this target or any dependence or dependences of dependences
and so on will be recomputed. This subroutine will get parameters: $_[0] - flat
text of current target and hashref of values of dependencies. This module should
guarantee that values of dependencies will be valid values even if value is
C<undef>. This code can return C<undef> value as a valid code return but author
doesn't recommend it. If C<CHI::Cascade> could not get a valid values of all
dependencies of current target before execution of this code the last will not
be executed (The C<run> will return C<undef>).

=back

=item run( $target )

This method makes a cascade computing if need and returns value for this target
If any dependence of this target of any dependencies of dependencies were
recomputed this target will be recomputed too.

=item touch( $target )

This method refreshes the time of this target. Here is analogy with L<touch>
utility of Unix and behaviour as L<make> after it. After L</touch> all targets
are dependent from this target will be recomputed at next L</run> with
an appropriate ones.

=back

=head1 STATUS

This module is experimental and not finished for new features ;-)
Please send me issues through L<https://github.com/Perlover/CHI-Cascade> page

=head1 CHI::Cascade & make

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
I<undef> value. A concurrent process should decide itself what it should do after
it - try again after few time or print some message like 'Please wait and try
again' to user.

=item Each target is splitted is two items in cache

For optimization this module keeps target's info by separately from value
item. A target item has lock & timestamp fields. A value item has a computed value.

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
	target	=> qr/unique_name_(.*)/,
	depends	=> sub { 'unique_name_other_' . $_[0] },
	code	=> sub {
	    my ($target_name, $values_of_depends) = @_;

	    # $this_name == 'unique_name_3' if $cascade->run('unique_name_3') was
	    # $values_of_depends == {
	    #     unique_name_other3 => $value_ref_3
	    # }
	}
    );

    $cascade->rule(
	target	=> qr/unique_name_other_(.*)/,
	code	=> sub {
	    my ($target_name, $values_of_depends) = @_;
	    ...
	}
    );

When we will do:

    $cascade->run('unique_name_52');

$cascade will find rule with qr/unique_name_(.*)/, will make =~ and will find
a depend as unique_name_other_52

=head1 AUTHOR

This module has been written by Perlover <perlover@perlover.com>

=head1 LICENSE

This module is free software and is published under the same terms as Perl itself.

=head1 SEE ALSO

=over

=item L<CHI>						- mandatory

=item L<CHI::Driver::Memcached::Fast>	- recommended

=item L<CHI::Driver::File>			- file caching

=back

=cut
