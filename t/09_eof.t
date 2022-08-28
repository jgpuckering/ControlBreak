# Test suite for ControlBreak

use strict;
use warnings;
use v5.18;      # minimum needed for Object::Pad

use Test::More tests => 1;

use FindBin;
use lib $FindBin::Bin . '/../lib';

use Capture::Tiny ':all';

my ($stdout, $stderr, $exit) = capture {
    synopsis();
};


my $expected = <<__EX__;
Canada,Alberta,1019942*
Canada,Ontario,3412129*
Canada,Quebec,2397919*
Canada total,,6829990**
USA,Arizona,1640641*
USA,California,4946673*
USA,Illinois,2756546*
USA,New York,9211759*
USA,Pennsylvania,1619355*
USA,Texas,2345606*
USA total,,22520580**
Grand total,,29350570***
__EX__


is $stdout, $expected;

sub synopsis {
    use v5.18;

    use lib $FindBin::Bin . '/../lib';

    use ControlBreak;

    # set up two levels, in minor to major order, and an extra level
    # for tracking the end of the file
    my $cb = ControlBreak->new( qw( District Country EOF ) );


    my $district_total = 0;
    my $country_total = 0;
    my $grand_total = 0;

    while (my $line = <DATA>) {
        chomp $line;

        my ($country, $district, $city, $population) = split ',', $line;

        my $subtotals = sub {
            # break on District (or Country) detected
            if ($cb->break('District')) {
                say join ',', $cb->last('Country'), $cb->last('District'), $district_total . '*';
                $district_total = 0;
            }

            # break on Country detected
            if ($cb->break('Country')) {
                say join ',', $cb->last('Country') . ' total', '', $country_total . '**';
                $country_total = 0;
            }

            # we've reached end of data
            if ($cb->break('EOF')) {
                say 'Grand total,,', $grand_total, '***';
            }

            $district_total += $population;
            $country_total  += $population;
            $grand_total    += $population;
        };
        
        # Test the values (minor to major order) using perl eof to
        # detect the last record of the file and trigger an EOF break.
        # See https://perldoc.perl.org/functions/eof
        $cb->test_and_do($district, $country, eof, $subtotals);
    }
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
