#$Id: solr_tester.pl,v 1.9 2019/06/11 18:00:53 tburtonw Exp tburtonw $
use LWP;
use LWP::UserAgent;
use URI::Escape;
use URI;
use Time::HiRes;

#XXX TODO: add sending a first * query to all shards to warm up solr

#XXX Move all this to a config file and hash
# SOLR = (production|dev)
my $SOLR = 'production';
#my $SLEEP = 10; # currently will only use if in production


my $USE_SHARDS ="TRUE";
# use doc values for facet queries and for coll_id fq
my $USE_DV = "FALSE";
my @DEV_SHARDS = qw(1 2 3 4 5 6 7 8 9 10 11 12);
@DEV_SHARDS = qw(1 2 3 4 5 6 7 8 9);


#http://solr-sdr-dev:8111/solr/core-1x/select?indent=on&q=ocr:aardvark&wt=json&shards=http://solr-sdr-dev:8111/solr/core-1x,http://solr-sdr-dev:8111/solr/core-2x


my $DEV_SHARD_BASE ='solr-sdr-dev:8111/solr/core-';

my $DEV_SHARD_REST = 'x';

my $NUM_HITS;# = "TRUE"; # set row=0 just to get num hits
my $DEBUG;# = "TRUE";
my $base_url;
my $results = {};
my @errors=();


my $shards_param;

if ($SOLR eq 'production')
{
    $shards_param= 'solr-sdr-search-1:8081/solr/core-1x,solr-sdr-search-2:8081/solr/core-2x,solr-sdr-search-3:8081/solr/core-3x,solr-sdr-search-4:8081/solr/core-4x,solr-sdr-search-5:8081/solr/core-5x,solr-sdr-search-6:8081/solr/core-6x,solr-sdr-search-7:8081/solr/core-7x,solr-sdr-search-8:8081/solr/core-8x,solr-sdr-search-9:8081/solr/core-9x,solr-sdr-search-10:8081/solr/core-10x,solr-sdr-search-11:8081/solr/core-11x,solr-sdr-search-12:8081/solr/core-12x';

}
else
{
    my @temp;

    #http://solr-sdr-dev:8111/solr/core-1x/select?indent=on&q=ocr:aardvark&wt=json&shards=http://solr-sdr-dev:8111/solr/core-1x,http://solr-sdr-dev:8111/solr/core-2x
    
    foreach my $shard (@DEV_SHARDS)
    {
	push (@temp,$DEV_SHARD_BASE . $shard . $DEV_SHARD_REST);
    }
    my $temp_string = join(',',@temp);
    
    $shards_param ='shards=' . $temp_string;
}

$ua = LWP::UserAgent->new;
$ua->agent("SolrTester ");

my $line_no = 0;
# warning header should match $out

#    $out = "$input_data->{'lid'}\t$input_data->{'qtime'}\t$results->{'qtime'}\t$results->{'solr_elapsed'}\t$input_data->{'numfound'}\t$results->{'num_found'}";

#XXX fix error reporting.  Right now error=NA always gets output if there is no error
my $header ="lid\tin_qtime\tqtime\tsolr_elapsed\tin_num_found\tnum_found\terror";


while(<>){
    chomp;
    $line_no++;
    my $hostpart;
    my $query;
    my $rest;
    my $input_data={};
     #skip input header but print output header
    my $url;
    
    if ($line_no == 1)
    {
	print "$header\n";
    }
    else{
	#MOVE to a subroutine!!!!
	#FIX THIS    my ($lid,$date,$time,$cgi,$qtime,$url,$numfound)=split(/\t/,$_);
	# cosider reading header!!
	
	my @in_fields = split(/\t/,$_);

	# top_n  qtime	numfound	lid	date	time	ip	query	cgi	url
	#head -1 sample200_worst_a
	# $qtime	$numfound	$lid	$ip	$query	$cgi	$timestamp	$second	$minute	$hour	dow	yday	url
#	lid	url	qtime	num_found
	$input_data={};
	$input_data->{'qtime'} = $in_fields[2];
	$input_data->{'num_found'} = $in_fields[3];
	$input_data->{'lid'} = $in_fields[0];
	# sample200	my $url = $in_fields[12];
	$url = $in_fields[1]; # top_n
	$url=~s/^\"*url=//;
	$url = clean_url($url);
	 ($hostpart,$query, @rest) = split(/\?/,$url);
	$rest = join('?', @rest);
	$query .= $rest;

    }

    if ($line_no == 1)
    {
	$query='*:*';
	$hostpart='http://solr-sdr-search-1:8081/solr/core-1x';
    }

    
        # modify query to use docValues
    if ($USE_DV eq 'TRUE'){
	$query =~s/facet\.field=([^\&]+)/$1_dv/g;
	# TODO when we reindex:  also modify coll_id fq to use doc values!
	#production does not have coll_id_dv but ht_collections coll_id is a dv field
    }

    # fix /etc/hosts on my machine so we don't need to do this
    # $hostpart =~s/(search\-\d+)\:8081/$1\.umdl\.umich\.edu\:8081/;
    # may work as a get, not needed as a post
    # my $escaped = URI::Escape::uri_escape_utf8($query);
    # #$url = $hostpart . '/select?' . $escaped;
    #why do we need to add /select?  check ls


    # this is to convert Solr4 urls to Solr6 urls 
    if($SOLR eq 'production')
    {
	$hostpart=fix_hostpart($hostpart);
	
	$url = $hostpart . '/select?' . $query;
    }
    else
    {
	my $num_shards = scalar(@DEV_SHARDS);
       	$head_shard_url = get_head_shard($num_shards);
	$url = $head_shard_url . $query;
    }
    
    if ($USE_SHARDS)
    {
	$url = $url . '&' . $shards_param;
	#XXX temporarily removing ampersand because getting double amp
#	$url = $url  . $shards_param;
    }
    
    #debugging below
    #print "\n--\n$url\n";
    #print_hash($input_data);
    #next;
    #exit;
    
    my $results = get_solr_response($url);
    my $out;
    my $error = "NA";
   
    if ($line_no != 1)
    {
	
	# XXX this must match header
	$out = "$input_data->{'lid'}\t$input_data->{'qtime'}\t$results->{'qtime'}\t$results->{'solr_elapsed'}\t$input_data->{'num_found'}\t$results->{'num_found'}";
    
	if (exists ($results->{'error'}))
	{
	    $error = $results->{'error'};
	    $error_line = $out . "\t$error";
	    push (@errors,$error_line);
	}
	$out = $out . "\t$error";
	print "$out\n";	
    }

    if (defined($SLEEP)){
	sleep($SLEEP);
	
    }
    
}
#XXX output the errors to a file    
   
    

#----------------------------------------------------------------------
sub get_solr_response
{
    my $url = shift;
    print STDERR "debug $url\n" if ($DEBUG);

    my $num_found = 0;
    my $qtime =      0;
    my $to_return = {};


    my $solr_start = Time::HiRes::time();
#    my $res = $ua->get($url);
    my $res = $ua->post($url);
    my $solr_elapsed = sprintf("%.3f", Time::HiRes::time()  - $solr_start);
    
    if ($res->is_success) 
    {
        print STDERR "$line_no success\!\n";
	$to_return->{'solr_elapsed'}= $solr_elapsed;

	my $content= $res->content;    
        my @lines=split(/\n/,$content);
        foreach my $line (@lines)
        {
	    if ($line=~/numFound\s*\"\:\s*(\d+)\,/)
	    {
	    	$num_found = $1;
	    	print "hits $num_found\n" if $DEBUG;
		$to_return->{'num_found'} = $num_found;
		
	    }
	    #"QTime":12,"
	    if ($line =~/QTime\"\:(\d+)\,/){
		$qtime=$1;
		print "qtime=$qtime\n" if $DEBUG;
		$to_return->{'qtime'} = $qtime;
	    }
	    
	    
        }
        #print "debug content\n===\n$content\n";
        
    }
    else 
    {
#        print $res->status_line, "\n$line_no\n";
        print STDERR $res->status_line, "\n$line_no\n--\nbad url is $url";
	$to_return->{'qtime'} = 0;
	$to_return->{'num_found'} = 0;
	$to_return->{'error'} = $res->status_line;
	
	
    }
    return ($to_return);
}


sub get_head_shard
{
    my $num_shards = shift;
    my $shard = int(rand($num_shards)+1);
    my $head_shard = 'http://' . $DEV_SHARD_BASE . $shard . $DEV_SHARD_REST . '/select?';
    return $head_shard;
}

#----------------------------------------------------------------------
sub print_hash
{
    my $h = shift;
    foreach my $key (sort keys %{$h}){
	print "$key\t$h->{$key}\n";
    }
    
}
#----------------------------------------------------------------------
sub clean_url
{
    my $url = shift;
    # Somehow R import export seems to be adding quotes at beginning and end of url string and doubling quotes in other parts of url
    #remove beginning and end qoutes
    $url =~s/^\"//;
    $url =~s/\"$//;
    #change double double quotes to regular double quotes
    $url =~s/\"\"/\"/g;

    # remove trailing blank fq= if it is there
    $url =~s/fq\=$//;
    # remove trailing ampersand if it is there
    $url =~s/\&$//;
    
    return $url;
    
    
    
}

#----------------------------------------------------------------------
# Not used.  This is copied from  Search::Searcher for reference
sub __get_request_object {
#    my $self = shift;
    my $uri = shift;

    my ($url, $query_string) = (split(/\?/, $uri));  

    # If this is a string of characters, translate from Perl's
    # internal representation to bytes to make HTTP::Request happy.
    # If it came from a terminal, it will probably be a sequence of
    # bytes already (utf8 flag not set).
    if (Encode::is_utf8($query_string)) {
        $query_string = Encode::encode_utf8($query_string);
    }

    my $req = HTTP::Request->new('POST', $url, undef, $query_string);

    $req->header( 'Content-Type' => 'application/x-www-form-urlencoded; charset=utf8'  );
    
    return $req;
}

#----------------------------------------------------------------------
# sub fix_hostpart
#
# for now translates most recent Solr 4 urls to most recent Solr 6 urls
# XXX may need fixing for older Solr urls or newer Solr 6 config
#----------------------------------------------------------------------
sub fix_hostpart
{
    my $h = shift;
    if ($h =~/serve/)
    {
	#Solr 4 url needs fixing
	#http://solr-sdr-search-7:8081/serve-7/core-1/
	#http://solr-sdr-search-7:8081/solr/core-7x/select
	$h =~s,\/core-1,,;
	$h =~s ,serve-(\d+),solr\/core-$1x,;
	
    }
    return($h);
    
}
