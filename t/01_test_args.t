# Test suite for ControlBreak

use strict;
use warnings;
use v5.18;      # minimum needed for Object::Pad

use Test::More tests => 2;
use Test::Exception;

use FindBin;
use lib "$FindBin::Bin/../lib";

use ControlBreak;
   
my $cb = ControlBreak->new( 'eq' );

throws_ok 
    { $cb->test() } 
    qr/[*]E[*] number of arguments to test[(][)] must match those given in new[(][)]/, 
    'test() croaks when number of arguments doesn\'t match new()';

my ($x, $y);
throws_ok 
    { $cb->test( $x, $y ) } 
    qr/[*]E[*] number of arguments to test[(][)] must match those given in new[(][)]/, 
    'test() croaks when number of arguments doesn\'t match new()';
