#!/bin/sh
#$Id: runtestsSlurmIfCacheWarmed.sh,v 1.1 2010/01/20 15:52:31 tburtonw Exp $


#http://assam.umdl.umich.edu/flags/web/lss-warming-YYYY-MM-DD

#URLROOT='http://assam.umdl.umich.edu/i/index_release/warming-'
#URLROOT='http://moxie-1.umdl.umich.edu/flags/web/lss-warming-'
URLROOT='http://141.213.128.167/flags/web/lss-warming-'
DATE=`date +%F` 
URL=${URLROOT}${DATE}

echo "url is $URL"
COUNT=0

until `wget -q -U SOLR  $URL -O - >/dev/null`
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
#BASEDIR=/l1/bin/l/ls/test
BASEDIR=/htapps/tburtonw.babel/pilsner/test
TESTPROG=${BASEDIR}/runtestsSlurm.pl

RUNDIR=SlurmTests/Isilon/prod
LOGDIR=${BASEDIR}/logs/Mirlyn/Solr1.3/${RUNDIR}
REPORTPROG=${BASEDIR}/processlog.pl

#DATE=`date +%b%d`
# add year
DATE=`date +%b%d-%Y`



REPORTDIR=${BASEDIR}/reports/${RUNDIR}/${DATE}
LOGDIR=${BASEDIR}/logs/${RUNDIR}/${DATE}

echo "reportdir is ${REPORTDIR}"
echo "LOGDIR is $LOGDIR"
    echo "running:  ${PERL} ${TESTPROG} -d ${LOGDIR}"
     ${PERL} ${TESTPROG} -d ${LOGDIR}
     sleep 30
     mkdir -p ${REPORTDIR}
echo "running:  ${PERL} ${REPORTPROG} -l ${LOGDIR}/all.processed.5000.log -r $REPORTDIR/all.processed.5000.log -t 600 -n 10000"
     ${PERL} ${REPORTPROG} -l ${LOGDIR}/all.processed.5000.log -r $REPORTDIR/all.processed.5000.log -t 600 -n 10000

