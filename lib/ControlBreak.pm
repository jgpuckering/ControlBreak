# ControlBreak.pm - Compare values during iteration to detect changes

# Done:
# - allowed arguments to new() and test() to be level names or a hash of level_name/operator pairs
# - allowed a + prefix on a level name to indicate we want numeric comparison
# - provided a comparison method that takes level_name/operator pairs and sets them
# - renamed field @_cached_values to @_test_values
# - converted public field $level to private field $_test_levelnum and provided a levelnum() method to access it
# - added private field $_test_levelname and provided a levelname() method to access it
# - updated test cases
# - updated POD

# To Do:
# - croak if continue not called at the end of each iteration
# - provide an accumulate method that counts and sums an arbitrary number of named variables
# - provide a is_break method that tests level for non-zero
# - provide method control() as a synonym for test()
# - provide a ditto option


=head1 NAME

ControlBreak - Compare values during iteration to detect changes

=head1 SYNOPSIS

    use Modern::Perl '2021';

    # use feature 'signatures';
    # no warnings 'experimental::signatures';

    use ControlBreak;

    # set up two levels, in minor to major order
    my $cb = ControlBreak->new( qw( District Country ) );


    my $country_total = 0;
    my $district_total = 0;

    while (my $line = <DATA>) {
        chomp $line;

        my ($country, $district, $city, $population) = split ',', $line;

        # test the values (minor to major order)
        $cb->test($district, $country);

        # break on District (or Country) detected
        if ($cb->levelnum >= 1) {
            say join "\t", $cb->last('Country'), $cb->last('District'), $district_total . '*';
            $district_total = 0;
        }

        # break on Country detected
        if ($cb->levelnum >= 2) {
            say join "\t", $cb->last('Country') . ' total', '', $country_total . '**';
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
        say join "\t", $cb->last('Country'), $cb->last('District'), $district_total . '*';
        say join "\t", $cb->last('Country') . ' total', '', $country_total . '**';
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

The B<ControlBreak> module provides a class that is used to detect
control breaks; i.e. when a value changes. Typically, the data being
retrieved or iterated over is ordered and there may be more than one
value that is of interest.  For example consider a table of
population data with columns for country, district and city, sorted
by sorted by country and district.  With this module you can create
an object that will detect changes in the district or country,
considered level 1 and level 2 respectively. The calling program can
take action, such as printing subtotals, whenever level changes are
detected.

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

use Carp            qw(croak);
use Scalar::Util    qw(dualvar);
use DDP;

# public attributes
field $iteration    :reader     { 0 };  # [0] counts iterations
field @level_names  :reader;            # [1] list of level names

# private attributes
field $_num_levels;                     # [2] the number of control levels
field %_levname                 {   };  # [3] map of levidx to levname
field %_levidx                  {   };  # [4] map of lenname to levidx
field %_comp_op;                        # [5] comparison operators
field %_fcomp;                          # [6] comparison functions
field $_test_levelnum           { 0 };  # [7] last level returned by test()
field $_test_levelname          { 0 };  # [8] last level returned by test()
field @_test_values;                    # [9] the values of the current test()
field @_last_values;                    # [10] the values from the previous test()

=head1 FIELDS

=head2 iteration

A readonly field that provides the current 1-based iteration number.

=head2 level_names

A readonly field that provides a list of the level names that were
provided as arguments to new().

=cut

######################################################################
# Constructor (a.k.a. the new() method)
######################################################################

=head1 METHODS

=head2 new ( <level_name> [, <lev_level_name> ]... )

Create a new ControlBreak object.

Arguments are user-defined names for each level, in minor to major
order.  The set of names must be unique, and they must each start
with a letter or underscore, followed by any number of letters,
numbers or underscores.

A level name can also begin with a '+', which denotes that a numeric
comparison will be used for the values processed at this level.

The number of arguments to new() determines the number of control levels
that will be monitored.  The variables provided to method test() must
match in number and datatype to these operators.

The order of the arguments corresponds to a hierachical level of
control, from lowest to highest; i.e. the first argument corresponds
to level 1, the second to level 2, etc.  This also corresponds
to sort order, from minor to major, when iterating through a data stream.

=cut

BUILD {
    croak '*E* at least one argument is required'
        if @_ == 0;

    foreach my $arg (@_) {
        croak '*E* invalid level name'
            unless $arg =~ m{ \A [+]? [[:alpha:]_]\w+ }xms;
    }

    $_num_levels = @_;

    my %lev_count;

    foreach my $arg (@_) {
        $lev_count{$arg}++;
        croak '*E* duplicate level name: ' . $arg
            if $lev_count{$arg} > 1;
        my $level_name = $arg;
        my $is_numeric = $level_name =~ s{ \A [+] }{}xms;
        push @level_names, $level_name;
        my $op = $is_numeric ? '==' : 'eq';
        $_comp_op{$level_name} = $op;
        $_fcomp{$level_name} = _op_to_func($op);
    }

    @_last_values = ( undef ) x $_num_levels;

    my $ii = 0;
    map { $_levname{$ii++} = $_ } @level_names;

    $ii = 0;
    map { $_levidx{$_} = $ii++ } @level_names;
}

######################################################################
# Public methods
######################################################################

=head2 comparison ( %ops_or_subs )

The comparison method accepts a hash of which sets the comparison
operations for the designated levels.  Keywords must match the level
names provide in new().  Values can be '==' for numeric comparison,
'eq' for alpha comparison, or anonymous subroutines.

Anonymous subroutines must take two arguments, compare them in some
fashion, and return a boolean. For example sub { uc($_[0]) eq
uc($_[1]) } would provide a case-insensitive alpha comparison.

All levels are provided with default comparison functions as determined
by new().  This method is provided so you can change one or more of
those defaults.  Any level name not referenced by keys in the
argument list will be left unchanged.

=cut

method comparison (%h) {
    while ( my ($level_name, $v) = each %h ) {
        croak '*E* invalid level name: ' . $level_name
            if not exists $_levidx{$level_name};
        $_comp_op{$level_name} = $v;
        $_fcomp{$level_name} = _op_to_func($v);
    }
}

=head2 continue

Saves the values most recently provided to the test() method so they
can be compared to new values on the next iteration.

On the next iteration these values will be accessible via the last()
method.

=cut

method continue {
    @_last_values = @_test_values;
}

=head2 reset

Resets the state of the object so it can be used again for another
set of iterations using the same number and type of control variables.

=cut

=head2 last ($level)

Returns the value (for the corresponding level) that was given to the
test() method called prior to the most recent one.

The argument can be a level name or a level number.

Normally this is used while iterating through a data stream.  When a
level change (i.e. control break) is detected, the current data value
has changed relative to the preceding iteration.  At this point it
may be necessary to take some action, such a printing a subtotal.
But, the subtotal will be for the preceding group of data and the
current value belongs to the next group.  The last() method allows
you to access the value for the group that was just processed so, for
example, the group name can be included on the subtotal line.

For example, if level names are 'X' and 'Y' and $cb->test($x, $y) was
the previous invocation of test(), then $cb->last('Y') returns the
value of $y on the previous iteration.

=cut

method last ($arg) {
    my $retval;

    if ( $arg =~ m{ \A \d+ \Z }xms ) {
        croak '*E* invalid level number: ' . $arg
            unless exists $_levname{$arg};
        $retval = $_last_values[$arg];
    } else {
        croak '*E* invalid level name: ' . $arg
            unless exists $_levidx{$arg};
        $retval = $_last_values[$_levidx{$arg}];
    }

    return $retval;
}

=head2 levelname

Return the level name for the most recent invocation of the test 
method.

=cut

method levelname () {
    return $_test_levelname;
}

=head2 levelnum

Return the level number for the most recent invocation of the test 
method.

=cut

method levelnum () {
    return $_test_levelnum;
}

=head2 reset

Resets the state of the object so it can be used again for another
set of iterations using the same number and type of control 
establish when the object was instantiated with new() and includes
any comparisons that were subsequently modified.

=cut

method reset () {
    $iteration = 0;
    @_last_values = ( undef ) x $_num_levels;
}

=head2 $level = test ( $var1 [, $var2 ]... ])

Submits the control variables for testing against the values from the
previous invocation -- if method continue() was called in between.

Testing is done in reverse order, from highest
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

    @_test_values = @args;

    $iteration++;

    my $is_break;
    my $lev_idx = 0;

    # process tests in reverse order of arguments; i.e. major to minor
    my $jj = @args;
    foreach my $arg (reverse @args) {
        $jj--;

        # on the first iteration, make the last values match the current
        # ones so we don't detect any control break
        $_last_values[$jj] //= $arg
            if $iteration == 1;

        my $level_name = $_levname{$jj};

        # compare the current and last values using the comparison function
        # if they don't match, then it's a control break
        $is_break = not $_fcomp{$level_name}->( $_last_values[$jj], $arg );

        if ( $is_break ) {
            # internally our lists use the usual zero-based indexing
            # but externally our level numbers are 1-based, where
            # 1 is the most minor control variable.  Level 0 is used
            # to denote no level; i.e. no control break.  Since zero
            # is treated as false by perl, and non-zero as true, we
            # can use the level number in a condition to determine if
            # there's been a control break; ie. $level ? 'break' : 'no break'
            $lev_idx = $jj + 1;
            last;
        }
    }
    my $lev_num = $lev_idx;

    $_test_levelnum  = $lev_num;
    $_test_levelname = $_levname{$jj};

    return;
}

######################################################################
# Private subroutines and functions
######################################################################
sub _op_to_func ($op) {

    my $fcompare;

    if ($op eq '==') {
        $fcompare = sub { $_[0] == $_[1] };
    }
    elsif ($op eq 'eq') {
        $fcompare = sub { $_[0] eq $_[1] };
    }
    elsif (ref $op eq 'CODE') {
        $fcompare = $op;
    }
    else {
        croak '*F* invalid comparison operator: ' . $op;
    }

    return $fcompare;
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
