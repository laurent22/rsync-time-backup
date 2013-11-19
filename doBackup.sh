#!/usr/bin/env bash


# -----------------------------------------------------------------------------
# Parameters
# -----------------------------------------------------------------------------

APPDIR="/DEMO_RSYNC"
RSYNC_TIMEBACKUP="$APPDIR/rsync_tmbackup.sh"
CONFIG_FOLDER="$APPDIR/conf/"
EXCLUDED_FILESUFFIX=".excluded"
CONF=$CONFIG_FOLDER$1


# -----------------------------------------------------------------------------
# Job Configuration - retrieve and check functions
# -----------------------------------------------------------------------------

function checkJobs() {
	NUMOFLINES=`ls $CONFIG_FOLDER/ | grep -v $EXCLUDED_FILESUFFIX | wc -l | awk '{print $1}'` 
	if [ $NUMOFLINES -eq 0 ]; then
		echo -e "\nNo configuration founds. \nCreate a configuration and put in the configuration folder: '`pwd`/$CONFIG_FOLDER'"
		exit 0
	fi
}

function printSupportedJobs() {
	checkJobs
	
	echo -e "\nPlease specify 'all' or one of the following job:"
	
	for i in `ls $CONFIG_FOLDER/ | grep -v excluded`;
	do
		echo -en "\t - "$i
		if [ -f "$CONFIG_FOLDER$i$EXCLUDED_FILESUFFIX" ]; then
			echo -en " (Exclusion file list found)"
		fi
		echo -en "\n"
	done
	echo "NOTE: if you specify 'all', I will make the backup for all the jobs!"	
}

# -----------------------------------------------------------------------------
# Main task
# -----------------------------------------------------------------------------


function doBackup() {
	echo $1
	echo "-----------------------------------------------------------------------------------"

	source $CONFIG_FOLDER$1
	echo -e "Source: "$SRC
	echo -e "Destination: "$DST
	EXCLUDED=$CONFIG_FOLDER$1$EXCLUDED_FILESUFFIX
	echo -en "Exclusion list: "
	if [ -f $EXCLUDED ]; then
		echo $EXCLUDED
	else
		echo "not specified"
		EXCLUDED=""
	fi
	echo -en "\n"

	NOW=$(date +"%Y-%m-%d-%H%M%S")
	LOG_FILE="$NOW.log"
	$RSYNC_TIMEBACKUP $SRC $DST $EXCLUDED | tee -a $LOG_FILE
	
	# copy log in the latest destination folder as future reminder
	cp $LOG_FILE $DST/latest
	rm $LOG_FILE
}

# -----------------------------------------------------------------------------
# Check input parameters
# -----------------------------------------------------------------------------

if [ $# -eq 0 ]
  then
    echo "No job supplied"
	printSupportedJobs
	exit 0
fi

ALL=false
if [ "$1" == "all" ]; then
	checkJobs
	ALL=true
elif [ ! -f "$CONF" ]; then
	echo "Job '$1' not exists"
	printSupportedJobs
	exit 0
fi


# -----------------------------------------------------------------------------
# Launch backup on job or all jobs
# -----------------------------------------------------------------------------

if  $ALL ; then
	for i in `ls $CONFIG_FOLDER/ | grep -v $EXCLUDED_FILESUFFIX`;
	do
		echo -en "Process job: "
		doBackup $i

		echo -e "***********************************************************************************"
		echo -e "***********************************************************************************\n\n\n"
	done
else
	echo -en "Process job: "
	doBackup $1
	echo -e "***********************************************************************************\n\n\n"
fi




