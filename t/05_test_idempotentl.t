# Test suite for ControlBreak

use strict;
use warnings;
use v5.18;      # minimum needed for Object::Pad

use Test::More tests => 18;

use FindBin;
use lib $FindBin::Bin . '/../lib';

use ControlBreak;
   
my $cb = ControlBreak->new( 'L1_alpha' );

note "Testing whether method test() is idempotent";

my @expected =  qw( 0      1       1        0        0        1         );   
foreach my $x ( qw( Ottawa Toronto Hamilton Hamilton Hamilton Vancouver ) ) {
    $cb->test( $x );
    my $expected = shift @expected;
    ok $cb->levelnum == $expected, $expected ? "break on $x" : "no break on $x";

    # repeat test() to see if the result changed
    $cb->test( $x );
    ok $cb->levelnum == $expected, 'second test result was unchanged';

    $cb->continue;
    
    ok $cb->last('L1_alpha') eq $x, 'continue saved current value as last value';
}
