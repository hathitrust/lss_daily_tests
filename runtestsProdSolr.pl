#!/usr/bin/perl -w
#$Id: runtestsProdSolr.pl,v 1.1 2015/03/10 19:50:43 tburtonw Exp tburtonw $#
use strict;
use LWP::UserAgent;
#use LWP::Debug qw(+);  # uncomment to generate debugging info 
use LWP::Authen::Basic;
#use WWW::Mechanize;
use Time::HiRes;
use Getopt::Long qw(:config auto_version auto_help);
use Pod::Usage;


BEGIN
{
    require '/htapps/tburtonw.babel/analysis/bin2/runtestsProdSolr.cfg';
    
}

my $Cfg={};
no strict;
$Cfg=$Config;
use strict;

my $DEBUG; #  = "true";  # set to undef to turn off
my $TESTING ; # ="true";

#my $TEST_TYPE= 'perl|ls_perl'
my $TEST_TYPE = 'perl';


my $LOGDIR;


if (!defined ($LOGDIR))
{
    $LOGDIR = $Cfg->{'log_base_dir'};
    $LOGDIR .='/testing' if $TESTING; 
}

my $BINDIR =$Cfg->{'bindir'};

my $URLDIR = $Cfg->{'url_base_dir'}; 
my $WARMUP_URLS = $URLDIR . '/warmup10thou';

my $CACHE_WARMUP_URLS="";

#my $CACHE_WARMUP_URLS ='/l1/bin/l/ls/test/data/urlfiles/newWarmup1600';
# run queries in order of least I/O intensive queries first so that if evictions occur they will be evicted
# skip this because each slurm now does own cache warming?
#my $CACHE_WARMUP_URLS ='/l1/bin/l/ls/test/data/urlfiles/newWarmup1600.slowest.last';

my $url;
my $rv;
my $ua = getUA($Cfg);

BEGIN
{
    # pod2usage settings
    my $help = 0;
    my $man = 0;

    $rv=GetOptions(    'h|help|?'              =>\$help, 
                       'man'                   =>\$man,
		       'd|dir|logdir:s'    =>\$LOGDIR,
                  );
    #print usage if return value is false (i.e. problem processing options)
    if (!($rv))
    {
        pod2usage(1)
    }
    pod2usage(1) if $help;
    pod2usage (-exitstatus=>0, -verbose =>2) if $man;
}


#======================================================================
#MAIN
#
# run tests 
#----------------------------------------------------------------------

# Make log directory 
my $cmd = "mkdir -p $LOGDIR";
doCommand($cmd);

doTests();

#----------------------------------------------------------------------
sub doCommand
{
    my $cmd = shift;
    print " would do command $cmd\n" if $DEBUG;
    return if $DEBUG;
    
    my $status = system ($cmd);
    if ($status == 0)
    {
        # success
        print "command $cmd \n\tstatus was 0\n";
    }
    else
    {
        # failure
        die "command $cmd failed with error status $status $!";
    }
}

#----------------------------------------------------------------------
sub doTests
{

    my $LS;

    # run tests
    
    $cmd = "mkdir -p $LOGDIR";
    doCommand($cmd);
    # this is to warm the OS cache using targeted queries 
    # we still do the regular warm-ups so we can compare the effect of doing the cache warming with not doing it.  The regular warm-up will probably evice some stuff from the cache.
# don't do this because slurm4/duff4 now doing it    
#warmCache($LOGDIR,$BINDIR,$CACHE_WARMUP_URLS);
    ##
    my $start_run =  Time::HiRes::time;
    doWarmups($LOGDIR,$BINDIR,$WARMUP_URLS);
    if ($TEST_TYPE eq 'perl')
    {
        runTests($LOGDIR,$BINDIR,$URLDIR,$LS);
    }
    elsif ($TEST_TYPE eq 'ls_perl')
    {
        $LS="true";
        runTests($LOGDIR,$BINDIR,$URLDIR,$LS);
    }
    
    my $elapsed =  Time::HiRes::time - $start_run;
    print STDERR "finshed testing   in $elapsed milliseconds\n";

    
}
#----------------------------------------------------------------------
sub runTests
{
    my ($LOGDIR,$BINDIR,$URLDIR,$LS) = @_;
    my @queryfiles=qw (  all.processed.5000);
    my $urlfile;
    
    
    foreach my $filename (@queryfiles)
    {
        my $cmd;        
        
        my $subdir="";
        if (defined($LS))
        {
            $subdir='/LSqueries';
        }

        $urlfile = $URLDIR .$subdir . '/' . $filename;

        my $flags = " -t 600 -u $urlfile --logdir $LOGDIR -interval 100 -numq 10000";
        if (defined($LS))
        {
            $flags = " --lsqueries" . $flags;
        }

        $cmd = $BINDIR . '/runqueries.pl'. $flags;

        $cmd = $BINDIR . '/runqueries.pl'. " -t 600 -u $urlfile --logdir $LOGDIR -interval 2 -numq 4" if $TESTING;
        doCommand($cmd);
    }
}
#----------------------------------------------------------------------

#----------------------------------------------------------------------
sub doWarmups
{
    my ($LOGDIR,$BINDIR,$WARMUP_URLS) = @_;
    $cmd = $BINDIR . '/runqueries.pl'. " -t 20  -u $WARMUP_URLS  --logdir $LOGDIR -interval 100 -numq 10000" ;
    $cmd = $BINDIR . '/runqueries.pl'. " -t 20  -u $WARMUP_URLS  --logdir $LOGDIR -interval 5 -numq 10" if $TESTING;
    doCommand($cmd);    
}

#----------------------------------------------------------------------
#----------------------------------------------------------------------
sub    warmCache
{
    my ($LOGDIR,$BINDIR,$CACHE_WARMUP_URLS) = @_;
    $cmd = $BINDIR . '/runqueries.pl'. " -t 120  -u $CACHE_WARMUP_URLS  --logdir $LOGDIR -interval 100 -numq 10000" ;
    doCommand($cmd);    
}


#======================================================================
# LWP/Mech routines for stopping/starting Solr and checking status
#------------------------------------------------------------------------------
sub checkReturn
{
	my ($rv,$successMsg,$failureMsg)= @_;
	if (! defined ($rv))
	{	
		handleError("$failureMsg");           
	}
        elsif($rv =~m/FAIL/)
        {
            handleError("$failureMsg");           
        }
        else	
	{
            print "$successMsg\n";
	}
}
#----------------------------------------------------------------------
sub handleError
{
	#XXX replace this with something better perhaps die with message?
	my $msg = shift;
	print "$msg\n";
        die "$msg";
        
}
#----------------------------------------------------------------------
sub doConnect
{
    my ($ua,$url) = @_;
    my $content;
    my $msg;
    
    my   $req = HTTP::Request->new(GET => "$url");
   #Replace below with standard error/content handling
    my  $res = $ua->request($req);

    # check the outcome
    if ($res->is_success) {
        $content= $res->content;
    }
    else {
        $msg = "Error: " . $res->status_line . "\n";
        handleError($msg)
    }
    return $content;
}
#----------------------------------------------------------------------
sub getContentOrError
{
    my ($ua,$url) = @_;
    my $toReturn;
    my $msg;
   
    my   $req = HTTP::Request->new(GET => "$url");
    my   $res = $ua->request($req);
    # check the outcome
    if ($res->is_success) {
        $toReturn= $res->content;
    }
    else {
        $toReturn = "Error: " . $res->status_line . "\n";
    }
    return $toReturn;
}
#----------------------------------------------------------------------
#======================================================================
#  Config routines
#----------------------------------------------------------------------

#----------------------------------------------------------------------
sub getUA
{
    my  $ua = LWP::UserAgent->new;
    return $ua;
    
}



#----------------------------------------------------------------------
__END__


=head1 SYNOPSIS


runtestsSlurm.pl [options]


   runtestsSlurm.pl -d /full/path/to/logdir  -l myLogFileName


=head1 Options:

=over 8



=item B<-d,--dir,--logdir> F<directory path>

Full path to the directory for log files

=item B<-l,--logfile> F<string>

Name of logfile.  Default is urlfilename.log. This will be appended to the log directory path


=item B<-h,--help>

Prints this help


=item B<--version>

Prints version and exits.

=back

=head1 DESCRIPTION

B<This program runs file of URLs containing Solr queries and logs the response>

=head1 ENVIRONMENT



=cut
