#!/l/local/bin/perl -w
#$Id: getSolrDataSlurm.pl,v 1.1 2009/11/23 20:34:05 tburtonw Exp $#

use LWP;
use LWP::UserAgent;

my $TIMEOUT = 60;

my $ua = LWP::UserAgent->new;
$ua->agent("SolrTester ");
$ua->timeout($TIMEOUT);  # set this to the largest interval we want to measure!

#TestIt();


#----------------------------------------------------------------------
#Test driver
sub TestIt
{
    my $DEBUG="true";
    my $LOG_BASE_DIR='/l1/bin/l/ls/test/logs/Mirlyn/testSolrData/slurms' ;


    #WARNING the directories $LOG_BASE_DIR AND $LOG_BASE_DIR/$NUM_DOCS must exist!


    my $mbooks3={"name"=>"mbooks-3","host"=> 'dev.solr-sdr.umdl.umich.edu:8080','solrDataDir'=>'/l1/idx/m/mbooks-3/data'};
    my $shard1={"name"=>"mbooks-ls-shard-1","host"=> 'dev.solr-sdr.umdl.umich.edu:8080','solrDataDir'=>'/l1/idx/m/mbooks-ls-shard-1/data'};
    my $shard2={"name"=>"mbooks-ls-shard-2","host"=> 'dev.solr-sdr.umdl.umich.edu:8080','solrDataDir'=>'/l1/idx/m/mbooks-ls-shard-2/data'};
    my $SolrInstances =[$shard1,$shard2];


    
    getSolrConfigs($DEBUG,$shardmap,$ua,$LOG_BASE_DIR);
    
    getSolrStats($DEBUG,$shardmap, $ua,$LOG_BASE_DIR, 'before');
    getSolrStats($DEBUG,$shardmap, $ua,$LOG_BASE_DIR, 'after');
    
}

#----------------------------------------------------------------------
sub getSolrConfigs
{
    my ($DEBUG,$shardmap,$ua,$LOG_BASE_DIR) = @_;
    my $schema_url_end = '/file/?file=schema.xml';
    my $config_url_end = '/file/?file=solrconfig.xml';
    # shardmap entry 1=>"http://solr-sdr-search-1:8081/serve-1",
    #   http://solr-sdr-search-7.umdl.umich.edu:8081/serve-7/admin/
    #   http://solr-sdr-search-7.umdl.umich.edu:8081/serve-7/admin/file/?file=solrconfig.xml
    #   http://solr-sdr-search-7.umdl.umich.edu:8081/serve-7/admin/stats.jsp

    foreach my $shard (sort {$a<=>$b} (keys %{$shardmap}))
    {
        my $base_url = $shardmap->{$shard} .'/admin' ;
        my $schema_url = $base_url . $schema_url_end;
        my $config_url = $base_url . $config_url_end;
        
        my $subdir = 'shard-' . $shard;
                
        my $schemafile = $LOG_BASE_DIR .'/'. $subdir  . "\.schema.xml";
        my $configfile = $LOG_BASE_DIR .'/'. $subdir . "\.solrconfig.xml";
        if ($DEBUG)
        {
            print STDERR "\n===\nschema url is $schema_url\n file is $schemafile\n";
            print STDERR "config url is $config_url\n config file is $configfile\n ";
            next;
        }
        
        open (my $schemafh, '>',$schemafile) || die "couldn't open  file $schemafile $!";
        open (my $configfh, '>',$configfile) || die "couldn't open  file $configfile $!";
 
        #print STDERR "schema_url is $schema_url\n";
        $schema = getURL($ua,$schema_url);
        print {$schemafh} $schema;
        
        # print STDERR "config_url is $config_url\n";
        $config =  getURL($ua,$config_url);
        print {$configfh} $config;
    }
}

#----------------------------------------------------------------------
sub getSolrStats
{
    my ($DEBUG,$shardmap, $ua,$LOG_BASE_DIR, $before_after) = @_;
    my $stat_url_end =  '/stats.jsp';
    

    foreach my $shard (sort {$a<=>$b} (keys %{$shardmap}))
    {
        my $stat_url = $shardmap->{$shard} .'/admin'  .$stat_url_end;
        my $subdir ='shard-'. $shard ;
        my $prefix = $LOG_BASE_DIR .'/' . $subdir;
        
        my $beforefile = $prefix . "\.SolrStatsStart";
        my $afterfile = $prefix .  "\.SolrStatsAfter";
        my $stats;

        if ($DEBUG)
        {
            print STDERR "\nstat url=$stat_url before file =$beforefile after=$afterfile $before_after\n";
            next;
        }

        if ($before_after =~/before/)
        {
            open (my $beforefh, '>',$beforefile) || die "couldn't open  file $beforefile $!";
            $stats= getURL($ua,$stat_url);
            print {$beforefh} $stats;
        }
        else
        {
            open (my $afterfh, '>',$afterfile) || die "couldn't open  file $afterfile $!";    
            $stats= getURL($ua,$stat_url);
            print {$afterfh} $stats;
        }
     }
    
}



sub getURL
{
    my ($ua,$url) =@_;
    my $res = $ua->get($url);
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

