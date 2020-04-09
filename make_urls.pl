# quick and dirty making urls for ls on alamo
# see programs in pilsner/test for more sophisticated models to use

my $base_url='http://tburtonw-full.babel.hathitrust.org/cgi/ls?q1=';
my $rest='&a=srchls';
my $url;


while (<>)
{
    chomp;
    my $q=$_;
    # do we need to convert quotes to hex?
    $url= $base_url . $q . $rest;
    print "$url\n";
}
