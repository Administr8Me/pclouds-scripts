#!/bin/bash

# backup2s3.sh
# Dave McCormick
# version 2.0.1

# please refer to the instructions on using this profile script at
# http://www.practicalclouds.com/content/guide/archivetos3

# 1.0 - initial, create a gzipped tar and upload it to s3
# 1.1 - add no read errors option to tar  for paths with s3fs 
#       mounts contained within them.
# 1.2 - Exclude any s3 mounts from the tar backup.  It doesn't
#       work properly to just ignore the errors and most of the 
#       time we actually want a backup of the files minus the S3 content.
# 2.0 - Change from s3cmd to using aws
# 2.0.1	Correct a crazy error calculating unix time!!

# Copyright 2011 David McCormick
# 
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
# 
#        http://www.apache.org/licenses/LICENSE-2.0
# 
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

# function backup_keepx 
# Take a tar backup of specified directories with a date/time stamp appended to 
# the archive name and copy somewhere to s3.
# We can keep X backups in the backup destination and remove older files to
# maintain this number.
#
# usage: backup_keepx -p "PATHS" -d destination  -k number
# -p directory paths to include in the archive
# -f filename of the backup file.
# -c specify an alternate .awssecret file to use to access S3
# -d s3 location of the backup bucket or folder
# -k number of copies to maintain of this file.
#
# WARNING: The archive file name can NOT include spaces.

function backup_keepx {
        local BACKUPPATHS=""
	local BPATH=""
	local TARFILE=""
        local SCFG="/root/.awssecret"
	local DEST=""
	local KEEP=""
	local ARCHIVEPATH="/tmp"
	local TIMSTAMP
	local RESULT
	local NUMFILES
	local NUMTODELETE
	local FOUNDFILES
	local FOUND
	local UNIXTIME
	local FILENAME
	local FILE
	local IGNOREREADERRORS=""

        while [[ "$1" != "" ]]
        do
                case $1 in
                        -f|-file)        shift
                                if [[ "$1" != "" ]]; then
                                        TARFILE=$1
                                        shift
                                else
                                        $logger "-f requires the name of the backup file"
                                        return 1
                                fi
                                ;;
                        -p|-path)        shift
                                if [[ "$1" != "" ]]; then
                                        BACKUPPATHS=$1
                                        shift
                                else
                                        $logger "-p requires a list of file/directory paths"
                                        return 1
                                fi
                                ;;
                        -c|-config)     shift
                                if [[ "$1" != "" ]]; then
                                        SCFG=$1
                                        shift
                                else
                                        $logger "-c requires an awsecret file path as a value!"
                                        return 1
                                fi
                                ;;
                        -d|-destination) shift
                                if [[ "$1" != "" ]]; then
                                        DEST=$1
                                        shift
                                else
                                        $logger "-d requires an a destination path as a value!"
                                        return 1
                                fi
                                ;;
                        -k|-keep) shift
                                if [[ "$1" != "" ]]; then
                                        KEEP=$1
                                        shift
                                else
                                        $logger "-k requires an number of backup files to keep as a value!"
                                        return 1
                                fi
                                ;;
                        *)      $logger "WARNING! Found an unmatched argument \"$1\""
                                shift
                                ;;
                esac
        done

	if [[ "$BACKUPPATHS" == "" ]]; then
		$logger "I require a list of file/directory paths as an argument!"
		return 1
	fi

	if [[ "$TARFILE" == "" ]]; then
		$logger "I require the name of the backup file as an argument!"
		return 1
	fi
	if [[ "$DEST" == "" ]]; then
		$logger "I require the a destination for backup file in S3 as an argument!"
		return 1
	fi

	if [[ "$DEST" =~ s3:// ]]; then
		DEST=${DEST#s3://}
	fi

	# check that we can access S3.
	#RESULT=`s3cmd --no-progress --config=$SCFG ls $DEST 2>&1 | grep "^ERROR"`
        RESULT=`aws --secrets-file=$SCFG ls $DEST 2>&1`
	if [[ "$?" != "0" ]]; then
		$logger "ERROR: I can't access the backup location in S3!"
		$logger "$RESULT"
		return 1
	fi 
	
	if [[ -d "/data" ]]; then
        	ARCHIVEPATH="/data"
	fi

	# check if any of the paths include a s3fs mount
	EXCLUDES=""
	for BPATH in $BACKUPPATHS
	do
		BPATH=`echo $BPATH| sed -e 's/\\//\\\\\\//g'`
		FOUND=`mount | awk "(\\\$1 == \"s3fs\" && \\\$3 ~ /^$BPATH/){print \\\$3}"`
		if [[ "$FOUND" != "" ]]; then
			$logger "Excluding the s3fs mount $FOUND..."
			EXCLUDES="$EXCLUDES --exclude=$FOUND"
		fi
	done

	# make the backup file
	TIMESTAMP=`date +%Y-%m-%d_%H-%M-%S`
	$logger "Creating backup archive file ${ARCHIVEPATH}/${TARFILE}_${TIMESTAMP}.tgz"
	$logger "Command: tar cfpz ${ARCHIVEPATH}/${TARFILE}_${TIMESTAMP}.tgz $BACKUPPATHS $EXCLUDES"
	#RESULT=`tar cvfpz ${ARCHIVEPATH}/${TARFILE}_${TIMESTAMP}.tgz $BACKUPPATHS 2>&1 | grep -i "^error"`
	tar cfpz ${ARCHIVEPATH}/${TARFILE}_${TIMESTAMP}.tgz $BACKUPPATHS $EXCLUDES 2>&1 >>/var/log/messages
	if [[ "$?" != "0" ]]; then
		$logger "ERROR: I couldn't archive the data..."
		rm -f ${ARCHIVEPATH}/${TARFILE}_${TIMESTAMP}.tgz
		return 1
	fi

	#copy it to the backup location
	$logger "Uploading ${ARCHIVEPATH}/${TARFILE}_${TIMESTAMP}.tgz to $DEST"
	#RESULT=`s3cmd --no-progress --config=$SCFG put ${ARCHIVEPATH}/${TARFILE}_${TIMESTAMP}.tgz $DEST 2>&1 | grep "^ERROR"`
	RESULT=`aws --secrets-file=$SCFG put $DEST/${TARFILE}_${TIMESTAMP}.tgz ${ARCHIVEPATH}/${TARFILE}_${TIMESTAMP}.tgz`
	if [[ "$?" != "0" ]]; then
       		$logger "ERROR: I could not write the backup file to S3! "
       		$logger "ERROR: $RESULT"
		rm -f ${ARCHIVEPATH}/${TARFILE}_${TIMESTAMP}.tgz
		return 1
	fi
	echo "$RESULT"
	rm -f ${ARCHIVEPATH}/${TARFILE}_${TIMESTAMP}.tgz

	# if we have specified a number of files to keep, we need to work out if we need to delete any files...
	if [[ "$KEEP" != "" ]]; then
		$logger "Keep $KEEP backup files"
		#NUMFILES=`s3cmd --no-progress --config=$SCFG ls $DEST/${TARFILE}* | wc -l`
		NUMFILES=`aws --simple --secrets-file=$SCFG ls $DEST/${TARFILE} | wc -l`
		$logger "There are $NUMFILES backup files"
		if [[ $NUMFILES -gt $KEEP ]]; then
			# work out how many files we need to delete
			NUMTODELETE=$(($NUMFILES - $KEEP))
			if [[ "$NUMTODELETE" == "1" ]]; then 
				$logger "Deleting the oldest file"
			else
				$logger "Deleting the $NUMTODELETE oldest files"
			fi
			# convert the date stamps into Unix time so we can sort by age 
			#FOUNDFILES=`s3cmd --no-progress --config=$SCFG ls $DEST/${TARFILE}* | awk '{printf "%s@@@%s|%s\n",$1,$2,$4}' `
			FOUNDFILES=`aws --simple --secrets-file=$SCFG ls $DEST/${TARFILE} | awk '{printf "%s@@@%s|%s\n",$2,$3,$4}' `
			if [[ "-f /tmp/timesort.$$" ]]; then
				rm -f /tmp/timesort.$$
			fi
			for FOUND in $FOUNDFILES
			do
				UNIXTIME=`echo $FOUND | awk -F\| '{print $1}'`
				UNIXTIME=`echo "$UNIXTIME" | sed -e 's/@@@/ /'`
				UNIXTIME=`date --utc --date="$UNIXTIME" +%s`
			
				echo "${UNIXTIME}|${FOUND}" >>/tmp/timesort.$$
			done

			# choose the NUMTODELETE oldest files
			DELETEFILES=`cat /tmp/timesort.$$ | sort -n | head -${NUMTODELETE}`
			rm -f /tmp/timesort.$$

			#delete them
			for FILE in $DELETEFILES
			do
				FILENAME=${FILE##*|}
				$logger "Deleting $FILENAME"
				#RESULT=`s3cmd --no-progress --config=$SCFG del $FILENAME 2>&1 | grep "^ERROR"`
				RESULT=`aws --secrets-file=$SCFG delete $DEST/$FILENAME 2>&1`
				if [[ "$?" != "0" ]]; then
					$logger "ERROR: I could not remove the file $FILENAME"
					$logger "ERROR: $RESULT"
				fi
			done
		else
			$logger "I do not need to remove any files"
		fi
	fi

	return 0
}


prog=$(basename $0)
logger="logger -t $prog"

# e.g.
#backup_keepx -f mywebbackup -p "/etc/httpd /var/www" -c /root/.awssecret-backups -d pclouds-backups -k 5

backup_keepx $@

