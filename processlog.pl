#!/usr/bin/perl -w
#$Id: processlog.pl,v 1.1 2015/03/10 19:51:07 tburtonw Exp tburtonw $#
use strict;
use Getopt::Long qw(:config auto_version auto_help);
use Pod::Usage;

# pod2usage settings
my $help = 0;
my $man = 0;

my $TIMEOUT=600; #This should match whatever was used so we report timeouts as taking 1 millisecond longer than the timeout.



# These variable affect the summary report
my $REPORT_SECONDS;# =1 ;
my $REPORT_DECILES;# =1  ;
my $REPORT_STATS =1  ;
my $LOGFILE ='';
my $REPORT_FILE='';
my $NUMDOCS = '';




#
my $rv=GetOptions(    'h|help|?'              =>\$help, 
                      'man'                   =>\$man,
                      'l|logfile:s'    =>\$LOGFILE,
                      'r|reportfile:s'    =>\$REPORT_FILE,  
                      't|timeout:i'    =>\$TIMEOUT,
                      'n|numdocs:i'    =>\$NUMDOCS,
                  );
#print usage if return value is false (i.e. problem processing options)
if (!($rv))
{
    pod2usage(1)
}
pod2usage(1) if $help;
pod2usage (-exitstatus=>0, -verbose =>2) if $man;

# we must have a logfile to process, everything else will default
if (! $LOGFILE)
{
    print STDERR "Must specify log file to process\n";
    pod2usage(1);
    exit;    
}
#======================================================================
# main
#======================================================================

my @times=();
my @sorted;
my @deciles;
my @seconds;
my @elapsed;
my     $USER_TIMEOUT =30; # set this to whatever ls is using for a timeout waiting for solr
my        $user_timeouts=0;
        
    



#XXX this must match similar line in runqueries.pl
my @report_fields=('qtime','hits','query','count','etime','error');# this is for order of report fields
my @metadata;

open ( my $logfh,'<',$LOGFILE) or die "couldn't open log file $LOGFILE $!";


while (<$logfh>)
{
    #XXX consider printing error reports somewhere so we can track down problems with query parsing
    next if (/hits/);# should we check first line for labels in right order?
    if (/^\s*\#/)
    {
        push (@metadata,$_);
        next;
    }
    
    my ($qtime,$hits,$query,$count,$etime,$error)=split(/\|/,$_);
    # remove query parsing errors from counts but write comment to log
    if ($error =~/(pars|null)/)
    {
        my $err_type=$1;
        
     my $error_msg="\#ERROR $err_type $_";   
     push (@metadata,$error_msg);
     next;
    }

    if ($error =~/timeout/)
    {
        #debug     print STDERR "ERROR TIMEOUT $error $_\n";
        $qtime=($TIMEOUT * 1000)+1;# timeout is 60 seconds and qtime is milliseconds

    }
    # timeouts in LS are 30 seconds and there will be a blank qtime
    if ($qtime !~/\d+/)
    {
      #  print STDERR "qtime not a number $qtime: $_\n";
        $qtime=30;
    }
    else
    {
        #XXX this run only
        #$qtime = $qtime * 1000;    
    }
    
    push (@times,$qtime);
    if ($qtime eq " " )
    {
       # print STDERR "qtime = $qtime line=$_\n";
    }
    
    if ($etime >= $USER_TIMEOUT)
    {
        $user_timeouts++;
    }

    $etime = int($etime * 1000);# etime reported in seconds so convert to milliseconds
    
    
    push (@elapsed,$etime);
    
    #XXX check that $qtime is numeric also catch other errors above
    my $seconds = int ($qtime/1000);
    push (@seconds,$seconds);
    
    
}

my $reportfh = get_reportfile($REPORT_FILE); #summary report
# header info, should include name of log file processed, and time to do run 
# these are produced by runqueries.pl and start with a "#"
print {$reportfh} "\#$LOGFILE\n";
print {$reportfh} "\#Run for $NUMDOCS documents\n";

foreach my $metadata (@metadata)
{
    print {$reportfh} $metadata;
}


if ($REPORT_SECONDS)
{
    print {$reportfh} "# Times in Seconds\n";
    
    @sorted = sort {$a <=> $b} @seconds;
}
else
{
    print {$reportfh} "# Times in Milliseconds\n";
    @sorted = sort {$a <=> $b} @times;
}

my $count = scalar(@sorted);
print {$reportfh} "# Number queries run=$count\n";


my $max =$sorted[$#sorted];
my $min =$sorted[0];

my $DEC = int ($count/10);
my $index;
my $decile;
my $i;
my $out;

if ($REPORT_DECILES)
{
    push(@deciles,$min);
    for $i (1..9)
    {
        $index=$DEC*$i ;       
        $decile =$sorted[$index];
        push (@deciles,$decile);
    }
    push(@deciles,$max);
    $out = join('|',@deciles);
    print {$reportfh} "$out\n";
}
if ($REPORT_STATS)
{
    my $stats = getStats(\@sorted);
    my $header='#avg|median|90th|99th';
    my $out = join('|',@{$stats});    
    $out ='qtime|' . $out;
    print  {$reportfh} "$header\n";
    print {$reportfh} "$out\n";
    my $elapsed_stats = getStats(\@elapsed);
    my $elapsed=join('|',@{$elapsed_stats});    
    $elapsed='etime|' . $elapsed;
    print {$reportfh} "$elapsed\n";
}

if ($user_timeouts > 0)
{
    print {$reportfh} "\#User timeout count = $user_timeouts\n";
}
#----------------------------------------------------------------------

sub getStats
{
    my $ary_ref=shift;
    my @sorted = sort {$a <=> $b} @{$ary_ref};
    my @stats;
    
    my $total;
    foreach my $time (@sorted)
    {
        $total+=$time;
    }
    my $average=int($total/scalar(@sorted));
    push (@stats,$average);


    for $i (5,9)
    {
         $index=$DEC*$i ;       
         $decile =$sorted[$index];
         push (@stats,$decile);
    }

    # add 99th percentile
    $index =$count - (int($count/100));
    my    $nintyninth =$sorted[$index];
    push (@stats,$nintyninth);
    return (\@stats);
}


sub get_reportfile{
    my $REPORT_FILE = shift;
    my $out;
    
    if ($REPORT_FILE)
    {
        #print STDERR "\nopening $REPORT_FILE\n";
        open ( $out,'>>',$REPORT_FILE) or die "couldn't open output file $REPORT_FILE $!";
    }
    else
    {
        open ( $out,'>-') or die "couldn't open output file STDOUT $!";
    }
    return $out;
}


__END__

=head1 SYNOPSIS

processlog.pl -l logfile [options]


write statistics to reportfile 

    processlog.pl -l logfile -r reportfile -q queryfile 


processlog.pl --man    Full manual page

=head1 Options:

=over 8

=item B<-l,--logfile>  F<fullpath to logfile>

full path to logfile to read and process


=item B<-r,--reportfile> F<full path to file for statistics report>

Full path to the file to send summary statistics.  Default is STDOUT


=item B<-t, --timeout> F<integer>

Timeout in seconds.  This should match whatever was used in runqueries.pl.  It is used to insert a value in the query time for queries that timedout or produced other errors so we can still calculate statistics

=item B<-h,--help>

Prints this help


=item B<--version>

Prints version and exits.

=back

=head1 DESCRIPTION

B<This program reads a specified log created by runqueries.pl and generates a statistical summary report>

=head1 ENVIRONMENT

=cut
