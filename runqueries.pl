#! /usr/bin/perl -w
#$Id: runqueries.pl,v 1.2 2016/08/08 21:47:25 tburtonw Exp tburtonw $ 

use LWP;
use LWP::UserAgent;
use Getopt::Long qw(:config auto_version auto_help);
use Pod::Usage;
use File::Basename;
use Time::HiRes;
use CGI;

$main::VERSION='$Id: runqueries.pl,v 1.2 2016/08/08 21:47:25 tburtonw Exp tburtonw $';

my $URLFILE ='';
my $LOG_DIR;
my $LOGFILE= '';
my $TIMEOUT = 60;
my $NUMQ =100;
my $INTERVAL=100;  #100; #write to log every INTERVAL urls
my $LS_QUERIES = ''; #"true" ; #'';  # process solr query responses by default. Set this to true to process response from ls app
my $HTTP_METHOD = "get";


# pod2usage settings
my $help = 0;
my $man = 0;
#

my @report_fields=('qtime','A_qtime','B_qtime','hits','query','count','etime','error');# this is for order of report fields



$rv=GetOptions(    'h|help|?'              =>\$help, 
                   'man'                   =>\$man,
                   'q|numq|numqueries:i'          =>\$NUMQ,
                   'u|urls|urlfile|i|infile=s'    =>\$URLFILE,
                   'l|logfile:s'    =>\$LOGFILE,
                   'd|dir|logdir=s'    =>\$LOG_DIR,
                   't|timeout:i'    =>\$TIMEOUT,
                   'w|interval:i'    =>\$INTERVAL,
                   'lsqueries' =>\$LS_QUERIES,
                   'm:s' =>\$HTTP_METHOD,
                  );
#print usage if return value is false (i.e. problem processing options)
if (!($rv))
{
    pod2usage(1)
}

pod2usage(1) if $help;
pod2usage (-exitstatus=>0, -verbose =>2) if $man;

print STDERR "http method is $HTTP_METHOD\n";

if (! $LOGFILE)
{
    $LOGFILE = $URLFILE . '.log';
}

my $logfile = $LOG_DIR . '/' . basename($LOGFILE);

open (URLFILE, '<',$URLFILE)|| die "couldn't open file $URLFILE $!"; 

$ua = LWP::UserAgent->new;
$ua->agent("SolrTester ");
$ua->timeout($TIMEOUT);  # set this to the largest interval we want to measure!

my $writes=0;# Counter to print header of report first time we write to disk
my $count =0;
my $data=[];


my $start_run =  Time::HiRes::time;

while (<URLFILE>)
{
    my $hash_ref={};
    $count++;

    
    $hash_ref->{count} = $count;    
    chomp;
    my $url=$_;
    print STDERR "$count\tgetting $url\n";
    
    $hash_ref->{url} = $url;    
    $hash_ref->{query}='';
    my $start  = Time::HiRes::time;

    my $res;
    if ($HTTP_METHOD eq 'get')
    {
        $res = $ua->get($url);
    }
    else
    {
        my ($url,$params)=getPostURL($url);
        $res = $ua->post($url,$params);
    }
        

    my $elapsed =  Time::HiRes::time - $start;
    $hash_ref->{etime}=$elapsed;

    if ($LS_QUERIES)
    {
        $hash_ref = parse_response_ls($res,$hash_ref);
    }
    else
    {
        $hash_ref = parse_response_solr($res,$hash_ref);
    }
    

    push (@{$data},$hash_ref);


    #write out data every $INTERVAL
    if ($count % $INTERVAL ==0)
    {
        print STDERR "writing $count to file\n";
        if ($writes <1)
        {
            write_report_header(\@report_fields,$data,$logfile);
        }
        write_report(\@report_fields,$data,$logfile);
        $writes++;
        $data=[];
    }

    last if ($count >=$NUMQ);
}
my $elapsed_run =  Time::HiRes::time - $start_run;



# report on last bit
write_report(\@report_fields,$data,$logfile);
print STDERR "elapsed time is $elapsed_run\n";

# put elapsed time for run as last line in log
open ( my $log, '>>',$logfile) || die "couldn't open log file $logfile $!";
print $log "\#elapsed time is $elapsed_run\n";
close $log;
#----------------------------------------------------------------------

#----------------------------------------------------------------------
sub getPostURL
{
    my $inurl = shift;
    my $params={};
    my $rest;
    
    my ($url,@rest)=split(/\?/,$inurl);
    # if there was a questionmarks anywhere else we put it back together
    if (scalar(@rest) > 1)
    {
         $rest= join("?",@rest);
    }
    else
    {
        $rest=$rest[0];
    }
    
#    print "DEBUG rest is $rest   "; 
    my $q=CGI->new($rest);
    $params = $q->Vars;
    #print STDERR "url is $url\n";
    
    return ($url,$params);    

}

#----------------------------------------------------------------------
sub write_report_header
{
    my $report_fields_ary_ref =shift;
    my $data_ary_ref = shift;
    my $logfile = shift;
    my $DELIM='|';

    open ( my $log, '>>',$logfile) || die "couldn't open log file $logfile $!";
    
    #header
    #first row with name of logfile?
    print {$log} "\# $logfile \n";
    
    foreach my $report_field (@{$report_fields_ary_ref})
    {
        print {$log} $report_field . $DELIM;
    }
    print {$log} "\n";
    close $log;    
}

#----------------------------------------------------------------------

sub write_report
{
    my $report_fields_ary_ref =shift;
    my $data_ary_ref = shift;
    my $logfile = shift;
    my $DELIM='|';

    open ( my $log, '>>',$logfile) || die "couldn't open log file $logfile $!";
    
    foreach my $hash_ref (@{$data_ary_ref})
    {
        
        foreach  my $field (@{$report_fields_ary_ref})
        {
            if ($field eq 'query')
            {
                my $query = get_query_from_url($hash_ref->{'url'});
                print {$log}  "$query" . $DELIM;                            
            }
            else
            {    
                if (defined $hash_ref->{$field})
                {
                    
                    print {$log} "$hash_ref->{$field} $DELIM";
                }
                else
                {
                        print {$log} " $DELIM";
                }
            }
        }
        print {$log} "\n";        
        #print "$hash_ref->{qtime}\n";
    }
    close $log;    
}   



#XXX this may not be very robust 
# Needs to be modified to work with ls queries
sub get_query_from_url
{
    my $url = shift;
    my $junk;
    my $q;
    
    if ($url=~/select/)
    {
        ($junk,$q)= split(/select\/\?/,$url);
    }
    else
    {
        # http://babel.hathitrust.org/cgi/ls?q1=Minoritenkonvent&a=srchls
        ($junk,$q)=split(/\?/,$url);
        $q=~s,^q1=,,;
    }
    

    my @params = split(/\&/,$q);
    my $query = $params[0];
    $query =~s/^q=//;
    return $query;
}

#----------------------------------------------------------------------

sub getURL
{
    my ($ua,$url) =@_;
#XXX read flag to switch between get and post
#    my $res = $ua->get($url);
    my $res = $ua->post($url);

    if ($res->is_success) 
    {
        my $content= $res->content;
        return $content;
    }
    else 
    {
        return $res->status_line;
    }

}

#----------------------------------------------------------------------
sub parse_response_ls
{
    my $res = shift;
    my $hash_ref = shift;
    my $A_qtime=0;
    my $B_qtime=0;
    my $Qtime=0;
    my $numFound;
    
    # Check the outcome of the response
    if ($res->is_success) {
        my $content= $res->content;
        #<span>Search Results: </span>662 items found for <span>Minoritenkonvent</span> in 0.006 sec.</div><div class="refine"><span xmlns=""><ul cl
# new <div class="SearchResults_status"><span>Search Results: </span>9 items found for <span>"rebecca goldman"</span> in <em>Full-Text + All Fields</em><span class="debug">
#        (in 0.036 sec.)</span></div>


        if ($content =~m,(\d+[\,\d+]*)\s+items\sfound,)
        {
            $numFound=$1;
	}
	else
	{
	    $numFound=0;
	}
	#"B_qtime":"0.269"
	#"A_qtime":"0.270"
	
	if ($content =~/A_qtime\"\:\"([^\"]+)\"/)
	{
	    $A_qtime=$1;
	}
	if ($content =~/B_qtime\"\:\"([^\"]+)\"/)
	{
	    $B_qtime=$1;
	}
	
	if ($content =~m,in\s(\d+\.\d+)\ssec,)
	{    
	    $Qtime=$1;
	}

	$Qtime =($Qtime * 1000);  #ls reports in seconds not milliseconds
	$hash_ref->{hits}=$numFound;
	$hash_ref->{qtime}=$Qtime;
	$hash_ref->{'A_qtime'}="$A_qtime";
	$hash_ref->{'B_qtime'}="$B_qtime";
	
	print STDOUT "Found=$numFound\tTime= $Qtime\n";
        $hash_ref->{error}='';# must have defined field
    }
    else {
        print $res->status_line, "\n";
        $hash_ref->{error}= $res->status_line;
    }
    return $hash_ref;
}
#----------------------------------------------------------------------
#----------------------------------------------------------------------
sub parse_response_solr
{
    my $res = shift;
    my $hash_ref = shift;
    
    # Check the outcome of the response
    if ($res->is_success) {
        my $content= $res->content;

        
        if ($content =~m, numFound=\"([^\"]+)",)
        {
            $numFound=$1;
            $hash_ref->{hits}=$numFound;
        }
        if ($content =~m,QTime\">([^<]+)<,)
        {
            $Qtime=$1;
            $hash_ref->{qtime}=$Qtime;
        }
        print STDERR "Found=$numFound\tTime= $Qtime\n";
        #  print $res->content;
        $hash_ref->{error}='';# must have defined field
    }
    else {
        print $res->status_line, "\n";
        $hash_ref->{error}= $res->status_line;
    }
    return $hash_ref;
}
#----------------------------------------------------------------------

__END__


=head1 SYNOPSIS


runqueries.pl [options]

run 15  queries using ./data/urlfile/2word.urls  write to log to ./data/logs/run1/2word.urls.log 
with a timeout of 50 seconds

   runqueries.pl -u ./data/urlfiles/2word.urls -numq 15  -d ./data/logs/run1 -t 50

run 15 queries but write log to /foo/bar/mylog.foo

   runqueries.pl -u ./data/urlfiles/2word.urls -numq 15  -d ./foo/bar/ -l mylog.foo

makequeries.pl --man    Full manual page

=head1 Options:

=over 8

=item B<-q,--numq,numqureies>  F<integer>

Number of queries to run
Default is 100


=item B<-u,-i,--urls, --urlfile,--infile> F<full path to input file of urls>

Full path to the input file containing a list of urls, one per line

=item B<-d,--dir,--logdir> F<directory path>

Full path to the directory for log files

=item B<-l,--logfile> F<string>

Name of logfile.  Default is urlfilename.log. This will be appended to the log directory path

=item B<-t, --timeout> F<integer>

Time in seconds to wait for a response from server
Default is 60 seconds


=item B<-h,--help>

Prints this help


=item B<--version>

Prints version and exits.

=back

=head1 DESCRIPTION

B<This program creates runs file of URLs containing Solr queries and logs the response>

=head1 ENVIRONMENT



=cut
