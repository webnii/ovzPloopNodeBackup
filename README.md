ovzPloopNodeBackup
==================
A script which will backup OpenVZ Ploop containers, transfer them to a remote server and retain four backups.


What does it to?
--------------
This script will backup OpenVZ Ploop containers and transfer them to an external server. Once transferred,
the script will verify that the backup exists on the external server and then rotate the backups in a
manner through which a total of four backups will be retained on the external server.

If the backup file is not created on the external server, the script will re-attempt transfer. If the backup
is still not created on the external server after the second attempt, the script will not delete the backup
on the local server and will send an error email advising that the backup will need to be manually transferred
and rotated.

**An SSH key relationship must exist between the local server and the backup server in order to be able
to transfer backups to the external server.**


What do I need to edit?
--------------
You should edit the variables within the DEFAULTS, VARIABLES, and COMMAND LOCATIONS of ovzPloopNodeBackup.sh.


Can backups be done automatically?
--------------
They sure can! We recommend setting up a cron task and redirecting output to a log to be reviewed at a later time
if necessary. 

For example, if you wanted to complete backups on Sunday and Wednesday at midnight and redirect output to a log
file, we recommend something such as the following. Please note that we also recommend setting nice and ionice
in order to make sure that the backup process isn't eating up all of your I/O and CPU.

The following will backup up all of the containers:

	0 0 * * 0,3 root /bin/nice -n 19 /usr/bin/ionice -c2 -n7 /path/to/script/ovzPloopNodeBackup.sh --all > /path/to/script/logs/backup.log


Credits
--------------
This script has been created by Webnii (http://www.webnii.com) in collaboration with the Ploop wiki page
(http://openvz.org/Ploop/Backup) as well as a script provided by Andreas Faerber (https://github.com/andreasfaerber/vzpbackup).