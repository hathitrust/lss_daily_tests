#!/bin/sh
#$Id: testProdSolrIfCacheWarmed.sh,v 1.4 2019/02/19 17:33:53 tburtonw Exp tburtonw $

# IP of hathitrust via the MACC load balancer.  Hostname might not get the MACC due to load balancing.

URLROOT='https://babel.hathitrust.org/flags/web/lss-warming-'
# filename is:  lss-warming-YYYY-MM-DD
DATE=`date +%F` 
URL=${URLROOT}${DATE}

echo "url is $URL"
COUNT=0

until `curl -A solr_tester -s --fail $URL --resolve "babel.hathitrust.org:443:141.213.128.184" >/dev/null`
      
do sleep 300  
  echo "trying to get cache warming flag"
# need limit here.  It tries every 5 minutes so 12 tries/hour
# starts at 6:10 so 9:10 would be 12 * 3 =36

  COUNT=`expr ${COUNT} + 1`
  echo ${COUNT}


  if [ ${COUNT} -gt 36 ]
      then
      TIME=`date`
      echo "Could not find flag file at  $TIME\n quitting!"
      exit
  fi
done

TIME=`date`
echo "cache warming finished. Starting tests at $TIME"


PERL=/usr/bin/perl

#old bindir was /htapps/tburtonw.babel/pilsner/test
BINDIR=/htapps/tburtonw.babel/analysis/gbin/gitbin
#/htapps/tburtonw.babel/analysis/bin2
TESTPROG=${BINDIR}/run_daily_tests.pl

# FIXME REPORTPROG=${BINDIR}/processlog.pl 

RUNDIR=Solr6
DATE=`date +%b%d-%Y`

#old logdir was /htapps/tburtonw.babel/pilsner/test/logs/SlurmTests/Isilon/prod
LOGDIR=/htsolr/lss-dev/data/4/daily_test_logs/logs/${RUNDIR}/${DATE}

#old reportdir was
#/htapps/tburtonw.babel/pilsner/test/reports/SlurmTests/Isilon/prod
#FIXME REPORTDIR=/htsolr/lss-dev/data/4/daily_test_logs/reports/${RUNDIR}/${DATE}


#echo "reportdir is ${REPORTDIR}"
echo "LOGDIR is $LOGDIR"
#mkdir -p ${REPORTDIR}
mkdir -p ${LOGDIR}
# shouldn't we check for errors?

echo "running:  ${PERL} ${TESTPROG} -d ${LOGDIR}"
${PERL} ${TESTPROG} -d ${LOGDIR}
#sleep 30

#FIXME
#echo "running:  ${PERL} ${REPORTPROG} -l ${LOGDIR}/all.processed.5000.log -r $REPORTDIR/all.processed.5000.log -t 600 -n 10000"
 #    ${PERL} ${REPORTPROG} -l ${LOGDIR}/all.processed.5000.log -r $REPORTDIR/all.processed.5000.log -t 600 -n 10000

