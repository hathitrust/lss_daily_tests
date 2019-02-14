#!/usr/bin/perl -w
#$Id: run_daily_tests.pl,v 1.2 2019/02/14 22:17:22 tburtonw Exp tburtonw $#
#
# Stripped down framework that sets up directories and runs
# daily tests using solr_tester.pl
#
# See /htapps/tburtonw.babel/analysis/bin2/runtestsProdSolr.pl
#  for ancestor of this program that did lots more:
#  stop/start solr?
#  warm cache
#  run warmup queries
#  run ls or solr queries  
#


use strict;
use Time::HiRes;
use Getopt::Long qw(:config auto_version auto_help);
use Pod::Usage;


BEGIN
{
    require '/htapps/tburtonw.babel/analysis/bin2/run_daily_tests.cfg';
}

my $Cfg={};
no strict;
$Cfg=$Config;
use strict;

my $DEBUG;#  = "true";  # set to undef to turn off
my $TESTING ; # ="true";

my $LOGDIR;
my $QUERY_FILE;

if (!defined ($QUERY_FILE))
{
    $QUERY_FILE = $Cfg->{'query_file'};
}


if (!defined ($LOGDIR))
{
    $LOGDIR = $Cfg->{'log_base_dir'};
    $LOGDIR .='/testing' if $TESTING; 
}

my $BINDIR =$Cfg->{'bindir'};




my $rv;


BEGIN
{
    # pod2usage settings
    my $help = 0;
    my $man = 0;

    $rv=GetOptions(    'h|help|?'              =>\$help, 
                       'man'                   =>\$man,
		       'd|dir|logdir:s'    =>\$LOGDIR,
		       'q|query_file:s'        =>\$QUERY_FILE,
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

    # run tests
    #XXX why are we doing this again?    
    $cmd = "mkdir -p $LOGDIR";
    doCommand($cmd);
    
    my $start_run =  Time::HiRes::time;
    runTests($LOGDIR,$BINDIR,$QUERY_FILE);
    my $elapsed =  Time::HiRes::time - $start_run;
    print STDERR "finshed testing   in $elapsed milliseconds\n";
    
}
#----------------------------------------------------------------------
sub runTests
{
    # rewrite to use solr_tester.pl
    # and day 95 logs
    my ($LOGDIR,$BINDIR,$QUERY_FILE) = @_;
        
    my $cmd;        
    # XXX could add params to solr_tester to use sleep or not?
    # currently logdir is the date and log.tsv the log name.
    # using the logdir allows us to do multiple runs/tests per day
    $cmd = "perl $BINDIR" . '/solr_tester.pl '. $QUERY_FILE . ' >> ' . $LOGDIR . '/log.tsv';
    doCommand($cmd);
}
#----------------------------------------------------------------------
__END__


=head1 SYNOPSIS


FIX THIS !!! runtestsSlurm.pl [options]


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
