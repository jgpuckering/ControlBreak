# ControlBreak.pm - Compare values during iteration to detect changes

# Done:
# -

# To Do:
# - provide a ditto option
# - change new to receive level names
# - allow a + prefix on a level name to indicate we want numeric comparison
# - allow arguments to new() and test() to be level names or a hash of level_name/operator pairs
# - provide a compare method that takes level_name/operator pairs and sets them
# - return a dualvar from the level method
# - provide method control() as a synonym for test()
# - provide a is_break method that tests level for non-zero
# - provide method L(<levname>) to return level number; e.g. if $cb->level > $cb->L('state')
# - croak if continue not called at the end of each iteration
# - provide a method to return a list of level name/number dualvars
# - provide an accumulate method that counts and sums an arbitrary number of named variables


=head1 NAME

ControlBreak - Compare values during iteration to detect changes

=head1 SYNOPSIS

    use Modern::Perl '2021';

    # use feature 'signatures';
    # no warnings 'experimental::signatures';

    use ControlBreak;

    # set up two levels, in minor to major order, both using string comparison
    my $cb = ControlBreak->new( 'eq', 'eq' );


    my $country_total = 0;
    my $district_total = 0;

    while (my $line = <DATA>) {
        chomp $line;

        my ($country, $district, $city, $population) = split ',', $line;

        # test the values (minor to major order)
        $cb->test($district, $country);

        # break on District (or Country) detected
        if ($cb->level >= 1) {
            say join "\t", $cb->last(2), $cb->last(1), $district_total . '*';
            $district_total = 0;
        }

        # break on Country detected
        if ($cb->level >= 2) {
            say join "\t", $cb->last(2) . ' total', '', $country_total . '**';
            $country_total = 0;
        }

        $country_total  += $population;
        $district_total += $population;
    }
    continue {
        # cache the current values (as received by ->test) as the new
        # 'last' values on the next iteration.
        $cb->continue();
    }

    # simulate break at end of data, if we iterated at least once
    if ($cb->iteration > 0) {
        say join "\t", $cb->last(2), $cb->last(1), $district_total . '*';
        say join "\t", $cb->last(2) . ' total', '', $country_total . '**';
    }

    __DATA__
    Canada,Alberta,Calgary,1019942
    Canada,Ontario,Ottawa,812129
    Canada,Ontario,Toronto,2600000
    Canada,Quebec,Montreal,1704694
    Canada,Quebec,Quebec City,531902
    Canada,Quebec,Sherbrooke,161323
    USA,Arizona,Phoenix,1640641
    USA,California,Los Angeles,3919973
    USA,California,San Jose,1026700
    USA,Illinois,Chicago,2756546
    USA,New York,New York City,8930002
    USA,New York,Buffalo,281757
    USA,Pennsylvania,Philadelphia,1619355
    USA,Texas,Houston,2345606

=head1 DESCRIPTION

The B<ControlBreak> module provides a class that is used to
detect control breaks; i.e. when a value changes during iteration.
Typically, the data being retrieved or iterated over is ordered and
there may be more than one value that is of interest.  For example
consider a table of population data with columns for country,
district and city, sorted by sorted by country and district.  With
this module you can create an object that will detect changes in the
district or country, considered level 1 and level 2 respectively.
The calling program can take action, such as printing subtotals,
whenever level changes are detected.

=cut

########################################################################
# perlcritic rules
########################################################################

## no critic [ProhibitSubroutinePrototypes]

# due to use of postfix dereferencing, we have to disable these warnings
## no critic [References::ProhibitDoubleSigils]

# perlcritic wants POD sections like VERSION, DIAGNOSTICS, CONFIGURATION AND ENVIRONMENT,
# and INCOMPATIBILITIES.  But so far these are unneeded so we'll disable these warnings
# here so that perlcritic gives the module a clean bill of health.

## no critic (Documentation::RequirePodSections)

########################################################################
# Libraries and Features
########################################################################
use Modern::Perl '2021';

use Object::Pad 0.66 qw( :experimental(init_expr) );

package ControlBreak;
class   ControlBreak 1.00;

use Carp    qw(croak);
use DDP;

# public attributes
field $level        :reader     { 0 };
field $iteration    :reader     { 0 };

# private attributes
field @_comp_op;
field @_fcomp;
field @_last_values;
field @_cached_values;
field $_num_levels;

=head1 FIELDS

=head2 level

A readonly field that provides the level number most recently
evaluated by the test() method.

=head2 iteration

A readonly field that provides the current 1-based iteration number.

=cut

######################################################################
# Constructor (a.k.a. the new() method)
######################################################################

=head1 METHODS

=head2 new ( <op> [, <op> ]... )

Create a new ControlBreak object.  Arguments are one or more comparison
operators, specified as strings (usually '==' or 'eq' for numeric and
alpha comparison respectively).

Anonymous subroutines are also permit, so long as they take
two arguments, compare them in some fashion, and return a boolean.
For example sub { uc($_[0]) eq uc($_[1]) }.

The number of arguments to new() determines the number of control levels
that will be monitored.  The variables provided to method test() must
match in number and datatype to these operators.

The order of the arguments corresponds to a hierachical level of
control, from lowest to highest; i.e. the first argument corresponds
to level 1, the second to level 2, etc.  This also corresponds
to sort order, from minor to major.

=cut

BUILD {
    croak '*E* at least one argument is required'
        if @_ == 0;

    $_num_levels = @_;
    @_comp_op = @_;

    foreach my $c (@_comp_op) {
        my $fcompare;
        if ($c eq '==') {
            $fcompare = sub { $_[0] == $_[1] };
        }
        elsif ($c eq 'eq') {
            $fcompare = sub { $_[0] eq $_[1] };
        }
        elsif (ref $c eq 'CODE') {
            $fcompare = $c;
        }
        else {
            croak '*F* invalid comparison operator: ' . $c;
        }

        push @_fcomp, $fcompare;
    }
    @_last_values = ( undef ) x $_num_levels;
}

######################################################################
# Public methods
######################################################################

=head2 last ($level)

Returns the last value (the one for the previous iteration) that was
given to the test() method for the corresponding level.  It is this
value which is being compared to the current value for the current
iteration.  For example, if $cb->test($x, $y) was the previous
invocation of test(), then $cb->last(2) returns the value of $y
on the previous iteration.

=cut

method last ($lev) {
    return $_last_values[$lev-1];
}

=head2 $level = test ( $var1 [, $var2 ]... ])

Submits the control variables for testing against the valued from the
previous iteration.  Testing is done in reverse order, from highest
to lowest (major to minor) and stops once a change is detected. Where
it stops determines the control break level.  For example, if $var2
changed, level 2 is returned.  I $var2 did not change, but $var1 did,
the level 1 is returned.  If nothing changes, then level 0 is
returned.

The return value can therefore be tested as a simple boolean, where 0
means there was no control break and non-zero means there was a
control break.  Or, the level number can be used for finer control.

=cut

method test (@args) {
    croak '*E* number of arguments to test() must match those given in new()'
        if @args != $_num_levels;

    @_cached_values = @args;

    $iteration++;

    my $is_break;
    my $lev = 0;

    for (my $jj=@args-1; $jj >= 0; $jj--) {

        $_last_values[$jj] //= $args[$jj]
            if $iteration == 1;

        $is_break = not $_fcomp[$jj]->( $_last_values[$jj], $args[$jj] );

        if ( $is_break ) {
            $lev = $jj + 1;
            last;
        }
    }

    $level = $lev;
    return $lev;
}

=head2 continue

Caches the current values provided to the test() method so they
can be compared on the next iteration.

=cut

method continue {
    @_last_values = @_cached_values;
}

=head2 continue

Resets the state of the object so it can be used again for another
set of iterations using the same number and type of control variables.

=cut

method reset {
    $iteration = 0;
    @_last_values = ( undef ) x $_num_levels;
}

1;

__END__
=head1 DEPENDENCIES

Object::Pad

=head1 BUGS AND LIMITATIONS

None reported.

=head1 AUTHOR

Gary Puckering
jgpuckering@rogers.com

=head1 LICENSE AND COPYRIGHT

Copyright 2022, Gary Puckering

This utility is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
