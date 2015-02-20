#!/usr/bin/perl -w
#$Id: runtestsSlurm.pl,v 1.7 2010/01/22 18:48:25 tburtonw Exp $#
use strict;
use LWP::UserAgent;
#use LWP::Debug qw(+);  # uncomment to generate debugging info 
use LWP::Authen::Basic;
#use WWW::Mechanize;
use Time::HiRes;
use Getopt::Long qw(:config auto_version auto_help);
use Pod::Usage;

#require '/l1/bin/l/ls/test/getSolrDataSlurm.pl';
require '/htapps/tburtonw.babel/pilsner/test/getSolrDataSlurm.pl';
BEGIN
{
#    require '/l1/bin/l/ls/test/runtestsSlurm.cfg';
    require '/htapps/tburtonw.babel/pilsner/test/runtestsSlurm.cfg';
}

my $Cfg={};
no strict;
$Cfg=$Config;
use strict;

my $DEBUG;# ="true"; # set to undef to turn off
my $TESTING ;# ="true";

#my $TEST_TYPE= 'JMeter|perl|ls_perl'
my $TEST_TYPE= 'perl';
#$TEST_TYPE='JMeter';

my $BUILDSERVE ="serve";  # "build" or "serve"
#my $ShardConfig='SINGLE'|'SHARDS'';
my $ShardConfig='SHARDS';
#WARNING!!! SINGLE will be a particular slurm and build  depending on runtests.cfg
#XXX consider moving 

my $LOG;
my $LOG_BASE_DIR;

if (!defined ($LOG_BASE_DIR))
{
    $LOG_BASE_DIR = $Cfg->{'log_base_dir'};
    $LOG_BASE_DIR .= '/SlurmTests/Isilon/prod';
    $LOG_BASE_DIR .= '/test';
    $LOG_BASE_DIR .='/testing' if $TESTING; 
}

my $BINDIR =$Cfg->{'bindir'};

my $URLDIR = $Cfg->{'url_base_dir'}; 
$URLDIR .='/Slurm/Isilon';

my $WARMUP_URLS = $URLDIR . '/warmup10thou';

my $CACHE_WARMUP_URLS="";

#my $CACHE_WARMUP_URLS ='/l1/bin/l/ls/test/data/urlfiles/newWarmup1600';
# run queries in order of least I/O intensive queries first so that if evictions occur they will be evicted
# skip this because each slurm now does own cache warming?
#my $CACHE_WARMUP_URLS ='/l1/bin/l/ls/test/data/urlfiles/newWarmup1600.slowest.last';


my $shardmap =getShardmap($ShardConfig,$BUILDSERVE);

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
                       'l|logfile:s'    =>\$LOG,
                       'd|dir|logdir:s'    =>\$LOG_BASE_DIR,
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
my $cmd = "mkdir -p $LOG_BASE_DIR";
doCommand($cmd);

#XXX talk with Sebastien about restarting tomcats and/or trash to cache
#my $hosts = getHosts($ShardConfig,$BUILDSERVE);
#restartTomcats($hosts);

# get solr config and schema files and copy to $LOG_BASE_DIR
print STDERR "getting solr config and schema files\n";

getSolrConfigs($DEBUG,$Cfg->{'shardmap'},$ua,$LOG_BASE_DIR);

my @loadrates;
my $threadsPerSecond;

if ($TEST_TYPE eq 'JMeter')
{
    @loadrates = qw ( 1 2 3 4 5 6 7 8 16);
    @loadrates = qw ( 2  4  8) if $TESTING;
    @loadrates=qw (8);

    foreach my $threadsPerSecond (@loadrates)
    {
        #XXX we need to do something to clear the OS cache between load tests.  
        #Check out some kind of fillCacheWithTrash that would work on the Slurms
        # only restart tomcats here if we are running multiple tests
        if (scalar (@loadrates) >1)
        {
            # XXX talk to sebastien     Only do this if using dev not prod!!!
            #        my $hosts = getHosts($ShardConfig,$BUILDSERVE);
            #       restartTomcats($hosts);

        }
        
        my $start_tests =  Time::HiRes::time;
        doTests($threadsPerSecond, $shardmap);
        my $elapsed_alltests =  Time::HiRes::time - $start_tests;
        print STDERR "finshed testing index   in  $elapsed_alltests milliseconds\n";
    }
}
else 
{
        doTests($threadsPerSecond,$shardmap);
}


#======================================================================
sub restartTomcats
{
    my $hosts = shift;
    print STDERR "trying to restart tomcat\n";
    die "restartTomcats must be rewritten for slurms";
    
    foreach my $host (@{$hosts})
    {
        my $hostNoPort = $host;
        $hostNoPort =~s/\:808[01]//;
        
        if ($host=~/8081/)
        {
            $cmd = 'ssh -t -i ~/.ssh/id_dsa_cvs ' .  $hostNoPort . ' sudo /etc/init.d/tomcat-serve restart';
            print STDERR "restarting *SERVE* tomcat on $hostNoPort\n";
        }
        else
        {
            $cmd = 'ssh -t -i ~/.ssh/id_dsa_cvs ' .  $hostNoPort . ' sudo /etc/init.d/tomcat-build restart';
            print STDERR "restarting build tomcat on $hostNoPort\n";
        }
        
    #XXX    doCommand($cmd);    
    }
    #sleep (30);
    #test that solrs are up after restart
    # check out getSolrConfigs 

}
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
    my $threadsPerSecond =shift;
    my $shardmap = shift;
    my $LS;
    
    my $LOGDIR;
    
    if (defined ($threadsPerSecond))
    {
        $LOGDIR = $LOG_BASE_DIR . '/' . "$threadsPerSecond" . '-threads';
    }
    my $cmd = "mkdir -p $LOG_BASE_DIR";
    doCommand($cmd);

    print STDERR "\n====\n" if $DEBUG;


#XXX Do we really want to start and stop Solr rather than tomcat?  This would happen betweeen each load testing run
# restartSolrs($shardmap);

    # run tests
    $LOGDIR = $LOG_BASE_DIR;
    
    $cmd = "mkdir -p $LOGDIR";
    doCommand($cmd);
    getSolrStats($DEBUG,$shardmap, $ua,$LOG_BASE_DIR,'before');
    ##
    # this is to warm the OS cache using targeted queries 
    # we still do the regular warm-ups so we can compare the effect of doing the cache warming with not doing it.  The regular warm-up will probably evice some stuff from the cache.
# don't do this because slurm4/duff4 now doing it    warmCache($LOGDIR,$BINDIR,$CACHE_WARMUP_URLS);
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
    elsif ($TEST_TYPE eq 'JMeter')
    {
        #  This is to run tests using jmeter

        if (defined ($threadsPerSecond))
        {
            $LOGDIR = $LOG_BASE_DIR . '/' . "$threadsPerSecond" . '-threads';
        }
        $cmd = "mkdir -p $LOGDIR";
        doCommand($cmd);

        
        my $Jparams = getJMeterParams($threadsPerSecond);
        # currently can't pass in file name due to jmeter parameter expansion
        # further investigation might allow this and then we could pass file 
        # name instead of using 2 different jmeter test plans

        
        my $JMETER_TESTPLAN = "$BINDIR/jmeter/";
        $JMETER_TESTPLAN .= getJmeterTestplan($ShardConfig);
        my $logname='all5000';
        runTestsJMeter($logname, $LOGDIR, $JMETER_TESTPLAN,$Jparams);
    }

    my $elapsed =  Time::HiRes::time - $start_run;
    print STDERR "finshed testing   in $elapsed milliseconds\n";

    # get after stats
    getSolrStats($DEBUG,$shardmap, $ua,$LOG_BASE_DIR, 'after');
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
#XXX TODO: find way to have less than 1000 users with repeats

sub getJMeterParams
{
    my $threadsPerSecond =shift;
    if ($threadsPerSecond <1 || $threadsPerSecond >16)
    {
        die "threads per second must be between 1 and 16 ";
    }
    
    my $num_users = 1000;
    $num_users = 2 if $TESTING;    
    # my $times = int (1000/$num_users);
    my $times=1; # 1000 threads so have threads only execute 1 time

    #XXX Clarify the relationship between numusers and times and thread persecond
    
    #
    # these are for the guassian random timer
    # see  http://www.ingrid.org/jajakarta/jmeter/1.7/docs/usermanual/component_reference.html#Gaussian_Random_Timer
    # dev_delay is the deviation?
    # delay is the constant
    # total delay = delay + (random (dev_delay))
   # see http://www.javaworld.com/javaworld/jw-07-2005/jw-0711-jmeter.html
    my $rampup = int($num_users/$threadsPerSecond);   
    my $Jparams = { 'num_users'=>"$num_users",
                    'times'=>"$times",
                    'rampup' =>"$rampup",
                    'dev_delay'=>'1000',
                    'delay'=>'500',
                  };
     
    return $Jparams;
    
}

#----------------------------------------------------------------------
sub  startSolr
{
    my ($ua,$SolrStartURL,$SolrStatsURL) = @_;

    if ($DEBUG)
    {
        my $debugmsg="startSolr: \$SolrStartURL = $SolrStartURL \$SolrStatsURL=$SolrStatsURL\n";
        print STDERR $debugmsg;
        return;
    }
    $url = $SolrStartURL;
    $rv=doConnect($ua,$url);
#    print "DEBUG rv isn startSolr is $rv\n";
    checkReturn($rv,"solr start requested","solr start page did not return");
    sleep(10);# XXX this should be configurable
    # check solr admin page to make sure solr is running
    $url = "$SolrStatsURL";
    #here we need to connect but also to check response for proper number of docs?
    my $Stats=doConnect($ua,$url);
    checkReturn($rv,"solr started","solr did not start (could not reach stats page)");
}
#----------------------------------------------------------------------
sub stopSolr
{    
    my ($ua,$SolrStopURL,$SolrStatsURL) =@_;
    if ($DEBUG)
    {
        my $debugmsg="stopSolr: \$SolrStopURL = $SolrStopURL \$SolrStatsURL = $SolrStatsURL\n";
        print STDERR $debugmsg;
        return;
    }
   
    my  $url = $SolrStopURL;
    my $rv = doConnect($ua,$url);
    checkReturn($rv,"solr stop requested","solr stop page did not return");
    sleep (10);
    # make sure its stopped
    $url = $SolrStatsURL;
    $rv = getContentOrError($ua,$url);
    if ($rv =~/503/)
    {
        print "Solr successfully stopped\n";
    }
    else
    {
        checkReturn($rv,"solr stopped","solr  did not stop");
    }
}
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

#----------------------------------------------------------------------
sub runTestsJMeter
{
    my ($logname,$LOGDIR, $JMETER_TESTPLAN,$Jparams) = @_;
    my $JMeter_logname = $logname . 'jmetertest.jtl';
    my $LOG = "$LOGDIR" . '/' . "$JMeter_logname";

    my $rampup= $Jparams->{'rampup'};         
    my $params = " -Jhttplient.timeout=0 "; # see jmeter.properties file this should mean no timeout
                                            #WARNING, must use httpclient sampler instead of http sampler!

    $params = "-Jnum_users=$Jparams->{'num_users'} -Jrampup=$rampup -Jtimes=$Jparams->{'times'}";
    $params .= " -Jdev_delay=$Jparams->{'dev_delay'} -Jdelay=$Jparams->{'delay'} ";
    $params .= " -n -l $LOG -t $JMETER_TESTPLAN";
    
    my $cmd = '/l/local/jmeter/bin/jmeter ' . $params; 
    # copy command to a log file so we have record of what the jmeter params were
    open (my $paramlog,'>>', "$LOGDIR/$logname") || die "tom fix this bad $LOGDIR/$logname $!";
    print {$paramlog} "$cmd\n";
    close($paramlog);
    
    doCommand($cmd);    
    
}


#----------------------------------------------------------------------
sub doWarmupsJMeter
{
    my ($LOGDIR,$BINDIR,$WARMUP_QUERIES, $WARMUP_JMETER) = @_;
    my $params = "-n -l $LOGDIR/warmups.jtl -t $WARMUP_JMETER -Jwarmup_queries=$WARMUP_QUERIES";
    my $cmd = '/l/local/jmeter/bin/jmeter ' . $params; 
    doCommand($cmd);    
}

#----------------------------------------------------------------------
# cat 32GB of files to /dev/null to fill OS disk cache with irrelevant material
#  Warning: this only works on pilsner i.e. 1 shard tests!
sub fillCacheWithTrash
{
    my $cmd ='cat /l1/idx/m/mbooks-3/data/slip-1000000-docs/_v7.frq /l1/idx/m/mbooks-3/data/slip-1000000-docs/_v7.tis > /dev/null';
    
    doCommand($cmd);    
}

#----------------------------------------------------------------------

#======================================================================
#  Config routines
#----------------------------------------------------------------------
sub getHosts
{
    my $ShardConfig = shift;
    my $BUILDSERVE  = shift;
    my $port = '8080';
    my $h_with_p; # single host with port
    my $hosts_with_ports = [];    

    if ($ShardConfig eq 'SINGLE')
    {
        push (@{$hosts_with_ports},$Cfg->{'single_instance'}->{'host'});
    }
    elsif($ShardConfig eq 'SHARDS')
    {
        if ($BUILDSERVE =~/serve/)
        {
            $port = '8081';
        }

       my $hosts=$Cfg->{'all_slurm_hosts'};
        #add ports
        foreach my $host (@{$hosts})
        {
            $h_with_p = $host . ':' . $port;
            push (@{$hosts_with_ports},$h_with_p)
        }
        
    }
    return $hosts_with_ports;
}
#----------------------------------------------------------------------
sub getSolrInstances
{
    my $ShardConfig = shift;
    my $BUILDSERVE  = shift;
    
    my $cfg ={};
    my @configs;
    my $hosts=[];
    my $instance_id;
    

    if ($ShardConfig eq 'SINGLE')
    {
        return ($Cfg->{'single_instance'});
    }
    elsif ($ShardConfig eq 'SHARDS')
    {
        #XXX this hack is totally dependent on naming convention
        my $shardmap =getShardmap($ShardConfig,$BUILDSERVE);
        my @shardnums=(sort { $a <=> $b } (keys %{$shardmap}) );


#my $slurm1 ={"name"=>"build-1",
#             "host"=> 'solr-sdr-1.umdl.umich.edu:8080',
#             'solrDataDir'=>'/l/solrs/build-1/data',
#             'solrConfDir'=>'/l/solrs/build-1/conf',
#            };
#            #        http://solr-sdr-search-1:8081/serve-1
        
        foreach my $shardnum (@shardnums )
        {
            my $solrhost=$shardmap->{$shardnum};
            
            my ($junk,$morejunk,$host,$instance_id) = split(/\//,$solrhost);
            
          
            $cfg = { "name"=>"$instance_id",
                     "host"=> "$host",
                     'solrDataDir'=>'/l1/solrs/' . $instance_id . '/data',
                     'solrConfDir'=>'/l1/solrs/' . $instance_id . '/conf',
                   };   
                
            push (@configs,$cfg);    
        }
        
        return (\@configs);
    }
    else
    {
        die "invalid \$ShardConfig $ShardConfig\: must be one of [SHARDS|SINGLE]\n";
    }
}
#----------------------------------------------------------------------
sub getLogBaseDir
{
    my ($LOG_BASE_DIR,$ShardConfig)=@_;

    my $SUBDIR;
    
    if ($ShardConfig eq 'SINGLE')
    {
        ASSERT(0,qq{sub getLogBaseDir not implemented for slurms})
    }
    #XXX REDO for slurms
    elsif ($ShardConfig eq 'SHARDS')
    {
        ASSERT(0,qq{sub getLogBaseDir not implemented for slurms})
    }
    else
    {
        die "bad shard config $ShardConfig $!";
    }
    
    my $DIR = $LOG_BASE_DIR . '/' . $SUBDIR;
    return $DIR;
}
#----------------------------------------------------------------------
sub getURLDIR
{
    my ($URL_BASE_DIR,$ShardConfig) = @_;
    my $SUBDIR='';    # single uses main directory 
    my $URLDIR;
    #XXX REDO for slurms
    if ($ShardConfig eq 'SHARDS')
    {
#        $SUBDIR='/Shards';
    }

    $URLDIR = $URL_BASE_DIR . $SUBDIR; 
    return ($URLDIR);
}
#----------------------------------------------------------------------
sub getUA
{
    my $Cfg=shift;
    my $pilsnerCreds=$Cfg->{'pilsnerCreds'};
    my $lagerCreds=$Cfg->{'lagerCreds'};
    my  $ua = LWP::UserAgent->new;
    my $hosts = $Cfg->{'hosts'};

    my $address;
    my $realm = 'Tomcat Manager Application';
    my $user = 'admin';
    my $pass ='s0lrmb00ks';
    
    foreach my $host (@{$hosts})
    {
        $address = $host;
        $ua->credentials(
                      $address,
                      $realm,
                      $user => $pass
                     );
    }
    
    return $ua;
    
}
#----------------------------------------------------------------------
sub getJmeterTestplan
{
    my ($ShardConfig)=@_;
    my $plan;
    #XXX REDO for slurms    
    
#    if ($ShardConfig eq 'TWO_SHARDS')
 
    $plan="All_SlurmsMulti" .'.jmx' ;
    return ($plan);
    
    
}

#----------------------------------------------------------------------
sub restartSolrs
{
    die "restartSolrs needs fixing for working with slurms";
    
    #XXX Some problem with credentials prevents this from working from pilsner to slurm1
    # for now comment out
    #XXX don't do this in production but for testing on build machine would want it.
# XXX This needs a total rewrite to work in the slurm environment

    my $shardmap = shift;
    # do we need to be passed the Cfg object?
    
    foreach my $shard (sort {$a<=>$b} (keys %{$shardmap}))
    {
#XXX this is broken.  We need creds for the 4 slurms/tomcats and then urls for each of the 3
# solrs
        my $Solr;
        
        my $SolrStopURL = 'http://' .$Solr->{'host'}.$Cfg->{'EndSolrStopURL'} . $Solr->{name};
        my $SolrStartURL= 'http://' .$Solr->{'host'}.$Cfg->{'EndSolrStartURL'}  . $Solr->{name} ;
        my $SolrStatsURL= 'http://' .$Solr->{'host'}.'/' . $Solr->{name} . $Cfg->{'EndSolrStatsURL'};
        
        stopSolr($ua,$SolrStopURL,$SolrStatsURL);    
        startSolr($ua,$SolrStartURL,$SolrStatsURL);    
    }
}

#----------------------------------------------------------------------
sub getShardmap
{
    my $ShardConfig = shift;
    my $BUILDSERVE = shift;
    if ($BUILDSERVE ne "serve")
    {
        die "testing against build not yet supported"
    }
    if ($ShardConfig eq "SHARDS")
    {
        return $Cfg->{'shardmap'};
    }

    else
    {
        die "only 'SHARDS' currently supported in getShardmap";
    }
}    
#----------------------------------------------------------------------
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
