# Test suite for ControlBreak

use strict;
use warnings;
use v5.18;      # minimum needed for Object::Pad

use Test::More tests => 15;
use Test::Exception;

use FindBin;
use lib $FindBin::Bin . '/../lib';

use ControlBreak;

my $cb;


$cb = ControlBreak->new( 'L1' );

throws_ok
    { $cb->test() }
    qr/[*]E[*] number of arguments to test[(][)] must match those given in new[(][)]/,
    'test() croaks when number of arguments doesn\'t match new()';

my ($x, $y);
throws_ok
    { $cb->test( $x, $y ) }
    qr/[*]E[*] number of arguments to test[(][)] must match those given in new[(][)]/,
    'test() croaks when number of arguments doesn\'t match new()';

throws_ok
    { $cb->last('123') }
    qr/[*]E[*] invalid level number: 123/,
    'last() croaks when given an invalid level number';

throws_ok
    { $cb->last('XXX') }
    qr/[*]E[*] invalid level name: XXX/,
    'last() croaks when given an invalid level name';


$cb = ControlBreak->new( '+L1_areacode', 'L2_country' );

throws_ok
    { $cb->comparison( XXX => 'eq' ) }
    qr/[*]E[*] invalid level name: XXX/,
    'comparison() croaks when given an invalid level name';

my @levnames = $cb->level_names;
my @expected =  ( 'L1_areacode', 'L2_country' );
is_deeply \@levnames, \@expected, 'method level_names';

$cb->test( '902', 'CA');
$cb->continue;
$cb->test( '860', 'US');
is $cb->levelname, 'L2_country', 'method levelname';

ok $cb->break(), 'break true test';
$cb->continue;
$cb->test( '860', 'US');
ok !$cb->break(), 'break false test';

throws_ok
    { $cb->break('XXX') }
    qr/[*]E[*] invalid level name: XXX/,
    'break croaks on invalid level name';

throws_ok
    { $cb->last(9) }
    qr/[*]E[*] invalid level number: 9/,
    'last(levelnum) croaks if levelnum is invalid';

$cb = ControlBreak->new( '+L1_areacode', 'L2_country', '+EOF' );

my $coderef = sub {};
($x, $y) = (605, 'y', 1);
ok $cb->test_and_do( $x, $y, eof, $coderef ) == 3, 'test_and_do with correct arg count and eof';

throws_ok
    { $cb->test_and_do( $x, $y, $coderef ) }
    qr/[*]E[*] test_and_do must have one more argument than new()/,
    'test_and_do croaks with wrong argument count';

$coderef = 'not code';

throws_ok
    { $cb->test_and_do( $x, $y, eof, $coderef ) }
    qr/[*]E[*] last argument of test_and_do must be a code reference/,
    'test_and_do croaks when last arg is not a code reference';

throws_ok
    { $cb->comparison( EOF => 'ZZZ' ) }
    qr/[*]E[*] invalid comparison operator: ZZZ/,
    'comparison croaks given an invalid operator';
    