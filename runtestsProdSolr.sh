#/bin/sh
#$Id: runtestsSlurm.sh,v 1.1 2010/01/20 15:52:31 tburtonw Exp $

PERL=/l/local/bin/perl
BASEDIR=/l1/bin/l/ls/test
TESTPROG=${BASEDIR}/runtestsSlurm.pl

RUNDIR=SlurmTests/Isilon/prod
LOGDIR=${BASEDIR}/logs/Mirlyn/Solr1.3/${RUNDIR}
REPORTPROG=${BASEDIR}/processlog.pl

DATE=`date +%b%d`

REPORTDIR=${BASEDIR}/reports/${RUNDIR}/${DATE}
LOGDIR=${BASEDIR}/logs/${RUNDIR}/${DATE}

echo "reportdir is ${REPORTDIR}"
echo "LOGDIR is $LOGDIR"
#if [  -e ${LOGDIR} ]
 #   then
  #  echo "aborting: logdir ${LOGDIR} already exists"
#else
#    echo "logdir $LOGDIR does not exist"
    echo "running:  ${PERL} ${TESTPROG} -d ${LOGDIR}"
     ${PERL} ${TESTPROG} -d ${LOGDIR}
     sleep 30
     mkdir -p ${REPORTDIR}
echo "running:  ${PERL} ${REPORTPROG} -l ${LOGDIR}/all.processed.5000.log -r $REPORTDIR/all.processed.5000.log -t 600 -n 10000"
     ${PERL} ${REPORTPROG} -l ${LOGDIR}/all.processed.5000.log -r $REPORTDIR/all.processed.5000.log -t 600 -n 10000
#fi
