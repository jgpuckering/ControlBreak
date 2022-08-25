# Test suite for ControlBreak

use strict;
use warnings;
use v5.18;      # minimum needed for Object::Pad

use Test::More tests => 4;
use Test::Exception;

use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok 'ControlBreak';

my $cb = new_ok 'ControlBreak' => [ 'eq' ];

can_ok $cb, qw(level iteration last test continue reset);

throws_ok 
    { ControlBreak->new } 
    qr/[*]E[*] at least one argument is required/, 
    'new() croaks with no arguments';
