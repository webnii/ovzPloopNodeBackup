#!/bin/sh
#
# ovzPloopNodeBackup.sh
#
# A script which will backup containers using Ploop on an
# OpenVZ node. This script only supports containers using
# Ploop.
#
# Backups may be taken while the container(s) are running.
# The backups may also be configured as a cron to automatically
# backup all or specific containers.
#
# This script is based on information from the Ploop wiki
# page at http://openvz.org/Ploop/Backup as well as a script
# provided by Andreas Faerber located at the following
# GitHub repository:
# https://github.com/andreasfaerber/vzpbackup
#
# The script above has been modified by Webnii Internet
# Services LLC (http://www.webnii.com) to provide the following
# functionalities:
# + SCP backups to an external server
# + Re-attempt transfer if the initial attempt was not
#   successful
# + Rotate backups on the external server in a manner
#   where a total of 4 backups are maintained before
#   being rotated off
# + Delete backups from the local server only after
#   being transferred to the external server and verified
# + Send an email on failure indicating that a manual
#   transfer and rotation of backups is necessary
#
#
# Author: Webnii (http://www.webnii.com)
#         In collaboration with the Ploop wiki page at:
#         http://openvz.org/Ploop/Backup
#         As well as a script provided by Andreas Faerber at:
#         https://github.com/andreasfaerber/vzpbackup
#         

## =====================================================
##
## DEFAULTS
##
## These are the defaults for the script when run
## without including option variables.
##
## =====================================================

# SUSPEND: Should the container be suspended while the backup is in
#          progress? [ no | yes]
SUSPEND=no

# BACKUP_DIR: The location where backups should be placed locally on
#             the node prior to being transferred to the external server.
BACKUP_DIR=/nearstore/backups/

# COMPRESS: Which method (if any) should be used to compress the backups
#           prior to the backups being transferred?
#           [ no | bz | pz | gz | xz ]
COMPRESS=gz

## =====================================================
##
## VARIABLES
##
## =====================================================

# EXCLUDE: If there are any containers that should not be backed up by
#          this script, you can list them here by their IDs.
EXCLUDE=""

# REMOTE_HOST: The name of the external server where the backups will be
#              copied to through SCP. Please note that the local server
#              must have access to the external server with an SSH key.
REMOTE_HOST="backup.server.com"

# REMOTE_DIR: The directory on the external server where the backups
#             will be copied to and rotated.
REMOTE_DIR="/backups/server/"

# MAIL_FROM: The email address that emails with errors should be sent FROM.
MAIL_FROM="backups@backup.local.com"

# MAIL_TO: The email address that emails with errors should be sent TO.
MAIL_TO="notify@me.com"

# MAIL_SUBJECT: The subject of error emails.
MAIL_SUBJECT="[ERROR] Backup Transport Error(s)"

## =====================================================
##
## COMMAND LOCATIONS
##
## =====================================================

# VZLIST_CMD: The location of the vzlist command. If unsure, this should
#             be able to be located by running "which vzlist".
VZLIST_CMD=/usr/sbin/vzlist

# VZCTL_CMD: The location of the vzctl command. If unsure, this should
#             be able to be located by running "which vzctl".
VZCTL_CMD=/usr/sbin/vzctl

# SCP_CMD: The location of the scp command. If unsure, this should
#             be able to be located by running "which scp".
SCP_CMD=/usr/bin/scp

# RM_CMD: The location of the rm command. If unsure, this should
#             be able to be located by running "which rm".
RM_CMD=/bin/rm

# SENDMAIL_CMD: The location of the sendmail command. If unsure, this should
#             be able to be located by running "which sendmail".
SENDMAIL_CMD=/usr/sbin/sendmail

## =====================================================
##
## SYSTEM VARIABLES (DO NOT CHANGE)
##
## =====================================================

# TIMESTAMP: The time stamp used in the backup's name prior to being
#            transferred to the external server.
TIMESTAMP=`date '+%Y%m%d%H%M%S'`

# MAIL_REQUIRED: This command should always be set to 0 here. It will be switched
#                to 1 automatically if an email needs to be sent with errors.
MAIL_REQUIRED=0

# MAIL_MESSAGE: If errors are present and an email is being sent, this will be
#               the start of the email.
MAIL_MESSAGE="The following errors were found during the backup process:\n\n"


## =====================================================
##
## END CUSTOMIZATIONS
##
## No customizations should need to be made after this
## point unless you are confident you know what you are
## doing.
##
## =====================================================

contains() {
    string="$1"
    substring="$2"

    case "$string" in
        *"$substring"*)
            return 1
        ;;
        *)
            return 0
        ;;
    esac

    return 0
}

## FUNCTIONS END

for i in "$@"
do
case $i in
    --help)
		echo "Usage: $0 [--suspend=<yes/no>] [--backup-dir=<Backup-Directory>] [--compress=<no/pz/bz/gz/xz>] [--all] <CTID> <CTID>"
		echo "Defaults:"
		echo -e "SUSPEND:\t\t$SUSPEND"
		echo -e "BACKUP_DIR:\t\t$BACKUP_DIR"
		echo -e "COMPRESS:\t\t$COMPRESS"
		exit 0;
    ;;
    --suspend=*)
    	SUSPEND=`echo $i | sed 's/[-a-zA-Z0-9]*=//'`
    ;;
    --exclude=*)
    	EXCLUDE="$EXCLUDE `echo $i | sed 's/[-a-zA-Z0-9]*=//'`"
    ;;
    --backup-dir=*)
    	BACKUP_DIR=`echo $i | sed 's/[-a-zA-Z0-9]*=//'`
    ;;
    --compress=*)
		COMPRESS=`echo $i | sed 's/[-a-zA-Z0-9]*=//'`
	;;
    --all)
    	CTIDS=`$VZLIST_CMD -a -Hoctid`
    ;;
    *)
		# Parse CTIDs here
		CTIDS=$CTIDS" "$i
    ;;
esac
done

echo SUSPEND: $SUSPEND
echo BACKUP_DIR: $BACKUP_DIR
echo COMPRESS: $COMPRESS
echo CTIDs to backup: $CTIDS
echo EXCLUDE the following CTIDs: $EXCLUDE

if [ "x$SUSPEND" != "xyes" ]; then
    CMDLINE="${CMDLINE} --skip-suspend"
fi
if [ -z "$CTIDS" ]; then
    echo ""
    echo "No CTs to backup (Either give CTIDs or --all on the command line)"
    exit 0
fi

for i in $CTIDS
do

CTID=$i

contains "$EXCLUDE" $CTID
CONTAINS=$?

if [ $CONTAINS -eq 1 ]; then
    echo "Excluding CTID $CTID .."
    continue;
fi

echo "================================================"
echo "= BACKUP SCRIPT"
echo "= STARTING $TIMESTAMP"
echo "= TO $REMOTE_HOST"
echo "= DIR $REMOTE_DIR"
echo "================================================"

# Check if the VE exists
if grep -w "$CTID" <<< `$VZLIST_CMD -a -Hoctid` &> /dev/null; then
	echo "Backing up CTID: $CTID"

	ID=$(uuidgen)
	VE_PRIVATE=$(VEID=$CTID; source /etc/vz/vz.conf; source /etc/vz/conf/$CTID.conf; echo $VE_PRIVATE)
	echo $ID > $VE_PRIVATE/vzpbackup_snapshot

	# Take CT snapshot with parameters
	$VZCTL_CMD snapshot $CTID --id $ID $CMDLINE

	# Copy the backup somewhere safe
	# We copy the whole directory which then also includes
	# a possible the dump (while being suspended) and container config
	cd $VE_PRIVATE
	HNAME=`$VZLIST_CMD -Hohostname $CTID`

	tar cvf $BACKUP_DIR${CTID}_${TIMESTAMP}.n.tar .

	# Compress the archive if wished
	if [ "$COMPRESS" != "no" ]; then
                echo -n "Compressing the backup archive "
				CMD_EXT=""
		if [ "$COMPRESS" == "bz" ]; then
			echo "with bzip2"
                        CMD="bzip2"
						CMD_EXT=".bz"
		elif [ "$COMPRESS" == "pz" ]; then
			echo "with pigz"
                        CMD="pigz"
						CMD_EXT=".pz"
		elif [ "$COMPRESS" == "gz" ]; then
			echo "with gzip"
                        CMD="gzip"
						CMD_EXT=".gz"
		elif [ "$COMPRESS" == "xz" ]; then
			echo "with xz"
                        CMD="xz --compress"
						CMD_EXT=".xz"
		fi
                if [ -r $BACKUP_DIR${CTID}_${TIMESTAMP}.n.tar ]; then
                    $CMD $BACKUP_DIR${CTID}_${TIMESTAMP}.n.tar
                else
                    echo "$BACKUP_DIR${CTID}_${TIMESTAMP}.n.tar not found!"
                fi
	fi

	# Delete (merge) the snapshot
	$VZCTL_CMD snapshot-delete $CTID --id $ID
	
	# SCP the backup to the backup server
	# Make directory first if necessary
	ssh ${REMOTE_HOST} "mkdir -p ${REMOTE_DIR}${CTID}"
	echo "Start: SCP to ${REMOTE_HOST}:${REMOTE_DIR}${CTID}/${CTID}.n.tar${CMD_EXT} "
	$SCP_CMD $BACKUP_DIR${CTID}_${TIMESTAMP}.n.tar${CMD_EXT} ${REMOTE_HOST}:${REMOTE_DIR}${CTID}/${CTID}.n.tar${CMD_EXT}
	echo "Finished: SCP to ${REMOTE_HOST}:${REMOTE_DIR}${CTID}/${CTID}.n.tar${CMD_EXT} "
	
	# Check if backup has been moved to remote server. If so, rotate and then delete from local server.
	# Only keep a total of 5 days of backups
	
	if ssh ${REMOTE_HOST} "test -e ${REMOTE_DIR}${CTID}/${CTID}.n.tar${CMD_EXT}"; then
		echo "Start: Rotate backups "
		ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${CTID}/${CTID}.3.tar${CMD_EXT} ] && mv -f ${REMOTE_DIR}${CTID}/${CTID}.3.tar${CMD_EXT} ${REMOTE_DIR}${CTID}/${CTID}.4.tar${CMD_EXT}"
		ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${CTID}/${CTID}.2.tar${CMD_EXT} ] && mv -f ${REMOTE_DIR}${CTID}/${CTID}.2.tar${CMD_EXT} ${REMOTE_DIR}${CTID}/${CTID}.3.tar${CMD_EXT}"
		ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${CTID}/${CTID}.1.tar${CMD_EXT} ] && mv -f ${REMOTE_DIR}${CTID}/${CTID}.1.tar${CMD_EXT} ${REMOTE_DIR}${CTID}/${CTID}.2.tar${CMD_EXT}"
		ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${CTID}/${CTID}.0.tar${CMD_EXT} ] && mv -f ${REMOTE_DIR}${CTID}/${CTID}.0.tar${CMD_EXT} ${REMOTE_DIR}${CTID}/${CTID}.1.tar${CMD_EXT}"
		ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${CTID}/${CTID}.n.tar${CMD_EXT} ] && mv -f ${REMOTE_DIR}${CTID}/${CTID}.n.tar${CMD_EXT} ${REMOTE_DIR}${CTID}/${CTID}.0.tar${CMD_EXT}"
		echo "Finished: Rotate backups "
		# Delete the backup from this server after it has moved
		echo "Start: Delete backup from this server "
		$RM_CMD $BACKUP_DIR${CTID}_${TIMESTAMP}.n.tar${CMD_EXT}
		echo "Finished: Delete backup from this server "
        
	else 
		# Backup transfer must have failed. Script will retry once more before discontinuing attempts.
		
		echo "ERROR! First backup transfer attempt appears to have failed."
		echo "Retrying transfer."
		
		# SCP the backup to the backup server
		# Make directory first if necessary
		ssh ${REMOTE_HOST} "mkdir -p ${REMOTE_DIR}${CTID}"
		echo "Start: SCP to ${REMOTE_HOST}:${REMOTE_DIR}${CTID}/${CTID}.n.tar${CMD_EXT} "
		$SCP_CMD $BACKUP_DIR${CTID}_${TIMESTAMP}.n.tar${CMD_EXT} ${REMOTE_HOST}:${REMOTE_DIR}${CTID}/${CTID}.n.tar${CMD_EXT}
		echo "Finished: SCP to ${REMOTE_HOST}:${REMOTE_DIR}${CTID}/${CTID}.n.tar${CMD_EXT} "
		
		# Check if backup has been moved to remote server. If so, rotate and then delete from local server.
		# Only keep a total of 5 days of backups
		
		if ssh ${REMOTE_HOST} "test -e ${REMOTE_DIR}${CTID}/${CTID}.n.tar${CMD_EXT}"; then
			echo "Start: Rotate backups "
			ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${CTID}/${CTID}.3.tar${CMD_EXT} ] && mv -f ${REMOTE_DIR}${CTID}/${CTID}.3.tar${CMD_EXT} ${REMOTE_DIR}${CTID}/${CTID}.4.tar${CMD_EXT}"
			ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${CTID}/${CTID}.2.tar${CMD_EXT} ] && mv -f ${REMOTE_DIR}${CTID}/${CTID}.2.tar${CMD_EXT} ${REMOTE_DIR}${CTID}/${CTID}.3.tar${CMD_EXT}"
			ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${CTID}/${CTID}.1.tar${CMD_EXT} ] && mv -f ${REMOTE_DIR}${CTID}/${CTID}.1.tar${CMD_EXT} ${REMOTE_DIR}${CTID}/${CTID}.2.tar${CMD_EXT}"
			ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${CTID}/${CTID}.0.tar${CMD_EXT} ] && mv -f ${REMOTE_DIR}${CTID}/${CTID}.0.tar${CMD_EXT} ${REMOTE_DIR}${CTID}/${CTID}.1.tar${CMD_EXT}"
			ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${CTID}/${CTID}.n.tar${CMD_EXT} ] && mv -f ${REMOTE_DIR}${CTID}/${CTID}.n.tar${CMD_EXT} ${REMOTE_DIR}${CTID}/${CTID}.0.tar${CMD_EXT}"
			echo "Finished: Rotate backups "
			
			# Delete the backup from this server after it has moved
			echo "Start: Delete backup from this server "
			$RM_CMD $BACKUP_DIR${CTID}_${TIMESTAMP}.n.tar${CMD_EXT}
			echo "Finished: Delete backup from this server "
		else 
			echo "ERROR! Second attempt to transfer backup has failed."
			echo "Backup will need be manually transferred."
			MAIL_REQUIRED=1
			MAIL_MESSAGE="${MAIL_MESSAGE=}---\nThe backup at $BACKUP_DIR${CTID}_${TIMESTAMP}.n.tar${CMD_EXT} could not be transferred to ${REMOTE_HOST}:${REMOTE_DIR}${CTID}/${CTID}.n.tar${CMD_EXT} after a total of 2 attempts.\n"
		fi
	fi
	
	
else
	echo "WARNING: No CT found for ID $CTID. Skipping..."
fi

# Send email with errors if there were errors
if [ $MAIL_REQUIRED -eq 1 ]; then
	echo "Errors were detected for one or more transfers!"
	echo "Sending email to ${MAIL_TO} with errors."
	MAIL_MESSAGE="${MAIL_MESSAGE=}\nPlease manually transfer and rotate the backups listed above."
	
	MAIL_FULL="subject:${MAIL_SUBJECT}\nfrom:${MAIL_FROM}\n${MAIL_MESSAGE=}"
	
	echo -e $MAIL_FULL | $SENDMAIL_CMD "${MAIL_TO}"
fi

done