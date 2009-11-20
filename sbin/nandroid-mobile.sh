#!/sbin/sh

# nandroid v2.2 - an Android backup tool for the G1 by infernix and brainaid
# restore capability added by cyanogen
# pensive modified to allow to add prefixes to backups, and to restore specific backups
# pensive added the ability to exclude various images from the restore/backup operations, allows to preserve the newer
# recovery image if an older backup is being restored or to preserve user data. Also, saves space by not backing up
# partitions which change rarely.
# pensive added compressing backups and restoring compressed backups
# pensive added fetching system updates directly from the web into /sdcard/update.zip
# pensive added moving *update*.zip from /sdcard/download where a browser puts it to /sdcard/update.zip
# pensive added deletion of stale backups

# Requirements:

# - a modded android in recovery mode (JF 1.3 will work by default)
# - adb shell as root in recovery mode if not using a pre-made recovery image
# - busybox in recovery mode
# - dump_image-arm-uclibc compiled and in path on phone
# - mkyaffs2image-arm-uclibc compiled and installed in path on phone
# - flash_image-arm-uclibc compiled and in path on phone
# - unyaffs-arm-uclibc compiled and in path on phone
# - for [de]compression needs gzip or bzip2, part of the busybox
# - wget for the wireless updates

# Reference data:

# dev:    size   erasesize  name
#mtd0: 00040000 00020000 "misc"
#mtd1: 00500000 00020000 "recovery"
#mtd2: 00280000 00020000 "boot"
#mtd3: 04380000 00020000 "system"
#mtd4: 04380000 00020000 "cache"
#mtd5: 04ac0000 00020000 "userdata"
#mtd6 is everything, dump splash1 with: dd if=/dev/mtd/mtd6ro of=/sdcard/splash1.img skip=19072 bs=2048 count=150

# We don't dump misc or cache because they do not contain any useful data that we are aware of at this time.

# Logical steps (v2.1):
#
# 0.  test for a target dir and the various tools needed, if not found then exit with error.
# 1.  check "adb devices" for a device in recovery mode. set DEVICEID variable to the device ID. abort when not found.
# 2.  mount system and data partitions read-only, set up adb portforward and create destdir
# 3.  check free space on /cache, exit if less blocks than 20MB free
# 4.  push required tools to device in /cache
# 5   for partitions boot recovery misc:
# 5a  get md5sum for content of current partition *on the device* (no data transfered)
# 5b  while MD5sum comparison is incorrect (always is the first time):
# 5b1 dump current partition to a netcat session
# 5b2 start local netcat to dump image to current dir
# 5b3 compare md5sums of dumped data with dump in current dir. if correct, contine, else restart the loop (6b1)
# 6   for partitions system data:
# 6a  get md5sum for tar of content of current partition *on the device* (no data transfered)
# 6b  while MD5sum comparison is incorrect (always is the first time):
# 6b1 tar current partition to a netcat session
# 6b2 start local netcat to dump tar to current dir
# 6b3 compare md5sums of dumped data with dump in current dir. if correct, contine, else restart the loop (6b1)
# 6c  if i'm running as root:
# 6c1 create a temp dir using either tempdir command or the deviceid in /tmp
# 6c2 extract tar to tempdir
# 6c3 invoke mkyaffs2image to create the img
# 6c4 clean up
# 7.  remove tools from device /cache
# 8.  umount system and data on device
# 9.  print success.


DEVICEID=foo
RECOVERY=foo

SUBNAME=""
NORECOVERY=0
NOBOOT=0
NODATA=0
NOSYSTEM=0
NOMISC=0
NOCACHE=0
NOSPLASH1=0
NOSPLASH2=0

COMPRESS=0
GETUPDATE=0
RESTORE=0
BACKUP=0
DELETE=0
WEBGET=0
AUTOREBOOT=0
AUTOAPPLY=0
ITSANUPDATE=0
ITSANIMAGE=0
WEBGETSOURCE=""
WEBGETTARGET="/sdcard"

DEFAULTUPDATEPATH="/sdcard/download"

DEFAULTWEBUPDATE=http://n0rp.chemlab.org/android/update-cm-3.6.8-signed.zip
# There really should be a clone link always pointing to the latest
#DEFAULTWEBUPDATE="http://n0rp.chemlab.org/android/latestupdate-signed.zip"
DEFAULTWEBIMAGE=http://n0rp.chemlab.org/android/cm-recovery-1.3.1-signed.zip

# Set up the default (for pensive at least) nameservers
NAMESERVER1=64.46.128.3
NAMESERVER2=64.46.128.4

# WiFi works, rmnet0 setup ???
# Do not know how to start the rmnet0 interface in recovery
# If in normal mode "ifconfig rmnet0 down" kills rild too
# /system/bin/rild& exits immediately, todo?

echo ""
echo "nandroid-mobile v2.1"
echo ""

DEVICEID=`cat /proc/cmdline | sed "s/.*serialno=//" | cut -d" " -f1`

# This is the default repository for backups
BACKUPPATH="/sdcard/nandroid/$DEVICEID"


# Cache,Boot,Data,Misc,Recovery,System,Splash1,Splash2
# BACKUPLEGEND, If all the partitions are backed up it should be "CBDMRS12"
# Enables the user to figure at a glance what is in the backup
BACKUPLEGEND=""

DEFAULTCOMPRESSOR=gzip
DEFAULTEXT=.gz
DEFAULTLEVEL=""

ASSUMEDEFAULTUSERINPUT=0

# Hm, have to handle old options for the current UI
case $1 in
    restore)
        shift
        RESTORE=1
        ;;
    backup)
        shift
        BACKUP=1
        ;;
    --)
        ;;
esac

for option in $(getopt --name="nandroid-mobile v2.1" -l norecovery -l noboot -l nodata -l nosystem -l nocache -l nomisc -l nosplash1 -l nosplash2 -l subname: -l backup -l restore -l compress -l getupdate -l delete -l path -l webget: -l webgettarget: -l nameserver: -l nameserver2: -l bzip2: -l defaultinput -l autoreboot -l autoapplyupdate -l help -- "cbruds:p:" "$@"); do
    case $option in
        --help)
            echo "Usage: $0 {--backup|--restore|--getupdate|--delete|--compress|--bzip2:ARG|--webget:URL} [options]"
            echo ""
            echo "--help                     Display this help"
            echo ""
            echo "-s | --subname: SUBSTRING  In case of --backup the SUBSTRING is"
            echo "                           the prefix used with backup name"
            echo "                           in case of --restore or -c|--compress|--bzip2 or"
            echo "                           --delete SUBSTRING specifies backups on which to"
            echo "                           operate"
            echo ""
            echo "-u | --getupdate           Will search /sdcard/download for files named"
            echo "                           *update*.zip, will prompt the user"
            echo "                           to narrow the choice if more than one is found,"
            echo "                           and then move the latest, if not unique,"
            echo "                           to sdcard root /sdcard with the update.zip name"
            echo "                           It is assumed the browser was used to put the *.zip"
            echo "                           in the /sdcard/download folder. -p|--path option"
            echo "                           would override /sdcard/download with the path of your"
            echo "                           choosing."
            echo ""
            echo "-p | --path DIR            Requires an ARGUMENT, which is the path to where "
            echo "                           the backups are stored, can be used"
            echo "                           when the default path /sdcard/nandroid/$DEVICEID "
            echo "                           needs to be changed"
            echo ""
            echo "-b | --backup              Will store a full system backup on $BACKUPPATH"
            echo "                           One can suppress backup of any image however with options"
            echo "                           starting with --no[partionname]"
            echo ""
            echo "-r | --restore             Will restore the last made backup which matches --subname"
            echo "                           ARGUMENT for boot, system, recovery and data"
            echo "                           unless suppressed by other options"
            echo "                           if no --subname is supplied and the user fails to"
            echo "                           provide any input then the latest backup is used"
            echo "                           When restoring compressed backups, the images will remain"
            echo "                           decompressed after the restore, you need to use -c|-compress"
            echo "                           or --bzip2 to compress the backup again"
            echo ""
            echo "-d | --delete              Will remove backups whose names match --subname ARGUMENT"
            echo "                           Will allow to narrow down, will ask if the user is certain."
            echo "                           Removes one backup at a time, repeat to remove multiple backups"
            echo ""
            echo "-c | --compress            Will operate on chosen backups to compress image files,"
            echo "                           resulting in saving of about 40MB out of 90+mb,"
            echo "                           i.e. up to 20 backups can be stored in 1 GIG, if this "
            echo "                           option is turned on with --backup, the resulting backup will"
            echo "                           be compressed, no effect if restoring since restore will"
            echo "                           automatically uncompress compressed images if space is available"
            echo ""
            echo "--bzip2: -#                Turns on -c|--compress and uses bzip2 for compression instead"
            echo "                           of gzip, requires an ARG -[1-9] compression level"
            echo ""
            echo "--webget: URL|\"\"         Requires an argument, a valid URL for an *update*.zip file"
            echo "                           If a null string is passed then the default URL is used"
            echo "                           Will also create an update.MD5sum file and update.name with the"
            echo "                           web link from where this update.zip came."
            echo ""
            echo "--nameserver: IP addr      Provide the first nameserver IP address, to override the default"
            echo ""
            echo "--nameserver2: IP addr     Provide the second nameserver IP address, to override the default"
            echo ""
            echo "--webgettarget: DIR        Target directory to deposit the fetched update, default is"
            echo "                           /sdcard"
            echo ""
            echo "--norecovery               Will suppress restore/backup of the recovery partition"
            echo "                           If recovery.img was not part of the backup, no need to use this"
            echo "                           option as the nandroid will not attempt to restore it, same goes"
            echo "                           for all the options below"
            echo ""
            echo "--noboot                   Will suppress restore/backup of the boot partition"
            echo ""
            echo "--nodata                   Will suppress restore/backup of the data partition"
            echo ""
            echo "--nosystem                 Will suppress restore/backup of the system partition"
            echo ""
            echo "--nocache                  Will suppress restore/backup of the cache partition"
            echo ""
            echo "--nomisc                   Will suppress restore/backup of the misc partition"
            echo ""
            echo "--nosplash1                Will suppress restore/backup of the splash1 partition"
            echo ""
            echo "--nosplash2                Will suppress restore/backup of the splash2 partition"
            echo ""
            echo "--defaultinput             Makes nandroid-mobile non-interactive, assumes default"
            echo "                           inputs from the user"
            echo ""
            echo "--autoreboot               Automatically reboot the phone after a backup, especially"
            echo "                           useful when the compression options are on -c|--compress| "
            echo "                           --bzip2 -level since the compression op takes time and"
            echo "                           you may want to go to sleep or do something else, and"
            echo "                           when a backup is over you want the calls and mms coming"
            echo "                           through, right?"
            echo ""
            echo "--autoapplyupdate          Once the specific update is downloaded or chosen from the"
            echo "                           sdcard, apply it immediately. This option is valid as a "
            echo "                           modifier for either --webget or --getupdate options."
            echo ""
            exit 0
            ;;
        --norecovery)
            NORECOVERY=1
            #echo "No recovery"
            shift
            ;;
        --noboot)
            NOBOOT=1
            #echo "No boot"
            shift
            ;;
        --nodata)
            NODATA=1
            #echo "No data"
            shift
            ;;
        --nosystem)
            NOSYSTEM=1
            #echo "No system"
            shift
            ;;
        --nocache)
            NOCACHE=1
            #echo "No cache"
            shift
            ;;
        --nomisc)
            NOMISC=1
            #echo "No misc"
            shift
            ;;
        --nosplash1)
            NOSPLASH1=1
            #echo "No splash1"
            shift
            ;;
        --nosplash2)
            NOSPLASH2=1
            #echo "No splash2"
            shift
            ;;
        --backup)
            BACKUP=1
            #echo "backup"
            if [ "$RESTORE" == 1 -o "$DELETE" == 1 -o "$GETUPDATE" == 1 -o "$WEBGET" ]; then
                echo "Backup, Restore, Delete, Getupdate, Webget are mutually exclusive"
                echo "Please, choose one option only!"
                exit 1
            fi
            shift
            ;;
        -b)
            BACKUP=1
            #echo "backup"
            if [ "$RESTORE" == 1 -o "$DELETE" == 1 -o "$GETUPDATE" == 1 ]; then
                echo "Backup, Restore, Delete, Getupdate, Webget are mutually exclusive"
                echo "Please, choose one option only!"
                exit 1
            fi
            shift
            ;;
        --restore)
            RESTORE=1
            if [ "$BACKUP" == 1 -o "$DELETE" == 1 -o "$GETUPDATE" == 1 ]; then
                echo "Backup, Restore, Delete, Update are mutually exclusive"
                echo "Please, choose one option only!"
                exit 1
            fi
            #echo "restore"
            shift
            ;;
        -r)
            RESTORE=1
            if [ "$BACKUP" == 1 -o "$DELETE" == 1 -o "$GETUPDATE" == 1 ]; then
                echo "Backup, Restore, Delete, Update are mutually exclusive"
                echo "Please, choose one option only!"
                exit 1
            fi
            #echo "restore"
            shift
            ;;
        --compress)
            COMPRESS=1
            #echo "Compress"
            shift
            ;;
        -c)
            COMPRESS=1
            echo "Compress"
            shift
            ;;
        --bzip2)
            COMPRESS=1
            echo "Compressing with bzip2"
            DEFAULTCOMPRESSOR=bzip2
            DEFAULTEXT=.bz2
            if [ "$2" == "$option" ]; then
                shift
            fi
            DEFAULTLEVEL="$2"
            shift
            ;;
        --getupdate)
            GETUPDATE=1
            if [ "$BACKUP" == 1 -o "$DELETE" == 1 -o "$RESTORE" == 1 -o "$COMPRESS" == 1 ]; then
                echo "Backup, Restore, Delete, Webget, Update, Compress are mutually exclusive"
                echo "Please, choose one option only!"
                exit 1
            fi
            shift
            ;;
        -u)
            GETUPDATE=1
            if [ "$BACKUP" == 1 -o "$DELETE" == 1 -o "$RESTORE" == 1 -o "$COMPRESS" == 1 ]; then
                echo "Backup, Restore, Delete, Update are mutually exclusive"
                echo "Please, choose one option only!"
                exit 1
            fi
            shift
            ;;
        --subname)
            if [ "$2" == "$option" ]; then
                shift
            fi
            #echo $2
            SUBNAME="$2"
            shift
            ;;
        -s)
            if [ "$2" == "$option" ]; then
                shift
            fi
            #echo $2
            SUBNAME="$2"
            shift
            ;;
        --path)
            if [ "$2" == "$option" ]; then
                shift
            fi
            echo $2
            BACKUPPATH="$2"
            DEFAULTUPDATEPATH="$2"
            shift 2
            ;;
        -p)
            if [ "$2" == "$option" ]; then
                shift
            fi
            #echo $2
            BACKUPPATH="$2"
            shift 2
            ;;
        --delete)
            DELETE=1
            if [ "$BACKUP" == 1 -o "$GETUPDATE" == 1 -o "$RESTORE" == 1 ]; then
                echo "Backup, Restore, Delete, Update are mutually exclusive"
                echo "Please, choose one option only!"
                exit 1
            fi
            shift
            ;;
        -d)
            DELETE=1
            if [ "$BACKUP" == 1 -o "$GETUPDATE" == 1 -o "$RESTORE" == 1 ]; then
                echo "Backup, Restore, Delete, Update are mutually exclusive"
                echo "Please, choose one option only!"
                exit 1
            fi
            shift
            ;;
        --webgettarget)
            if [ "$2" == "$option" ]; then
                shift
            fi
            WEBGETTARGET="$2"
            echo "Target folder: $2"
            shift
            ;;
        --webget)
            if [ "$2" == "$option" ]; then
                shift
            fi
            #echo "WEBGET"
            # if the argument is "" stick with the default: /sdcard
            if [ ! "$2" == "" ]; then
                WEBGETSOURCE="$2"
            fi
            WEBGET=1
            shift
            ;;
        --nameserver)
            if [ "$2" == "$option" ]; then
                shift
            fi
            NAMESERVER1="$2"
            shift
            ;;
        --nameserver2)
            if [ "$2" == "$option" ]; then
                shift
            fi
            NAMESERVER2="$2"
            shift
            ;;
        --defaultinput)
            ASSUMEDEFAULTUSERINPUT=1
            shift
            ;;
        --autoreboot)
            AUTOREBOOT=1
            shift
            ;;
        --autoapplyupdate)
            AUTOAPPLY=1
            if [ "$WEBGET" == 0 -a "$GETUPDATE" == 0 ]; then
                echo "The --autoapplyupdate option is valid only in conjunction with --webget or --getupdate."
                echo "Aborting."
                exit 1
            fi
            shift
            ;;
        --)
            shift
            break
            ;;
    esac
done


if [ "$RESTORE" == 0 -a "$BACKUP" == 0 -a "$DELETE" == 0 -a "$GETUPDATE" == 0 -a "$WEBGET" == 0 -a "$COMPRESS" == 0 ]; then
	echo "Usage: $0 {-b|--backup|-r|--restore|-d|--delete|-u|--getupdate|--webget|--compress|--bzip2} [options]"
	echo "At least one operation must be defined, try $0 --help for more information"
	exit 0
fi

if [ ! "$SUBNAME" == "" ]; then
    if [ "$BACKUP" == 1 ]; then
        if [ "$COMPRESS" == 1 ]; then
            echo "Using $SUBNAME- prefix to create a compressed backup folder"
        else
            echo "Using $SUBNAME- prefix to create a backup folder"
        fi
    else
        if [ "$RESTORE" == 1 -o "$DELETE" == 1 -o "$COMPRESS" == 1 ]; then
            echo "Searching for backup directories, matching $SUBNAME, to delete or restore"
            echo "or compress"
            echo ""
        fi
    fi
else
    if [ "$BACKUP" == 1 ]; then
        echo "Using G1 keyboard, enter a prefix substring and then <CR>"
        echo -n "or just <CR> to accept default: "
        if [ "$ASSUMEDEFAULTUSERINPUT" == 0 ]; then
            read SUBNAME
        else
            echo "Accepting default."
        fi
        echo ""
        if [ "$COMPRESS" == 1 ]; then
            echo "Using $SUBNAME- prefix to create a compressed backup folder"
        else
            echo "Using $SUBNAME- prefix to create a backup folder"
        fi
        echo ""
    else
        if [ "$RESTORE" == 1 -o "$DELETE" == 1 -o "$COMPRESS" == 1 ]; then
            echo "Using G1 keyboard, enter a directory name substring and then <CR>"
            echo -n "to find matches or just <CR> to accept default: "
            if [ "$ASSUMEDEFAULTUSERINPUT" == 0 ]; then
                read SUBNAME
            else
                echo "Accepting default."
            fi
            echo ""
            echo "Using $SUBNAME string to search for matching backup directories"
            echo ""
        fi
    fi
fi

if [ "$BACKUP" == 1 ]; then
		mkyaffs2image=`which mkyaffs2image`
		if [ "$mkyaffs2image" == "" ]; then
			mkyaffs2image=`which mkyaffs2image-arm-uclibc`
			if [ "$mkyaffs2image" == "" ]; then
				echo "error: mkyaffs2image or mkyaffs2image-arm-uclibc not found in path"
				exit 1
			fi
		fi
		dump_image=`which dump_image`
		if [ "$dump_image" == "" ]; then
			dump_image=`which dump_image-arm-uclibc`
			if [ "$dump_image" == "" ]; then
				echo "error: dump_image or dump_image-arm-uclibc not found in path"
				exit 1
			fi
		fi
fi

if [ "$RESTORE" == 1 ]; then
		flash_image=`which flash_image`
		if [ "$flash_image" == "" ]; then
			flash_image=`which flash_image-arm-uclibc`
			if [ "$flash_image" == "" ]; then
				echo "error: flash_image or flash_image-arm-uclibc not found in path"
				exit 1
			fi
		fi
		unyaffs=`which unyaffs`
		if [ "$unyaffs" == "" ]; then
			unyaffs=`which unyaffs-arm-uclibc`
			if [ "$unyaffs" == "" ]; then
				echo "error: unyaffs or unyaffs-arm-uclibc not found in path"
				exit 1
			fi
		fi
fi
if [ "$COMPRESS" == 1 ]; then
                compressor=`busybox | grep $DEFAULTCOMPRESSOR`
                if [ "$compressor" == "" ]; then
                    echo "Warning: busybox/$DEFAULTCOMPRESSOR is not found"
                    echo "No compression operations will be performed"
                    COMPRESS=0
                else
                    echo "Found $DEFAULTCOMPRESSOR, will compress the backup"
                fi
fi

# 1
DEVICEID=`cat /proc/cmdline | sed "s/.*serialno=//" | cut -d" " -f1`
RECOVERY=`cat /proc/cmdline | grep "androidboot.mode=recovery"`
if [ "$RECOVERY" == "foo" ]; then
	echo "Error: Must be in recovery mode, aborting"
	exit 1
fi
if [ "$DEVICEID" == "foo" ]; then
	echo "Error: device id not found in /proc/cmdline, aborting"
	exit 1
fi
if [ ! "`id -u 2>/dev/null`" == "0" ]; then
	if [ "`whoami 2>&1 | grep 'uid 0'`" == "" ]; then
		echo "Error: must run as root, aborting"
		exit 1
	fi
fi


if [ "$RESTORE" == 1 ]; then
		ENERGY=`cat /sys/class/power_supply/battery/capacity`
		if [ "`cat /sys/class/power_supply/battery/status`" == "Charging" ]; then
			ENERGY=100
		fi
		if [ ! $ENERGY -ge 30 ]; then
			echo "Error: not enough battery power"
			echo "Connect charger or USB power and try again"
			exit 1
		fi
		mount /sdcard 2>/dev/null
		if [ "`mount | grep sdcard`" == "" ]; then
			echo "error: unable to mount /sdcard, aborting"
			exit 1
		fi

		# find the latest backup, but show the user other options
                echo ""
                echo "Looking for the latest backup, will display other choices!"
                echo ""

		RESTOREPATH=`ls -trd $BACKUPPATH/*$SUBNAME* 2>/dev/null | tail -1`
                echo " "

		if [ "$RESTOREPATH" = "" ];
		then
			echo "Error: no backups found"
			exit 2
		else
                        echo "Default backup is the latest: $RESTOREPATH"
                        echo ""
                        echo "Other available backups are: "
                        echo ""
                        ls -trd $BACKUPPATH/*$SUBNAME* 2>/dev/null | grep -v $RESTOREPATH
                        echo ""
                        echo "Using G1 keyboard, enter a unique name substring to change it and <CR>"
                        echo -n "or just <CR> to accept: "
                        if [ "$ASSUMEDEFAULTUSERINPUT" == 0 ]; then
                            read SUBSTRING
                        else
                            echo "Accepting default."
                            SUBSTRING=""
                        fi
                        echo ""

                        if [ ! "$SUBSTRING" == "" ]; then
                            RESTOREPATH=`ls -trd $BACKUPPATH/*$SUBNAME* 2>/dev/null | grep $SUBSTRING | tail -1`
                        else
                            RESTOREPATH=`ls -trd $BACKUPPATH/*$SUBNAME* 2>/dev/null | tail -1`
                        fi
                        if [ "$RESTOREPATH" = "" ]; then
                               echo "Error: no matching backups found, aborting"
                               exit 2
                        fi
		fi
		
		echo "Restore path: $RESTOREPATH"
                echo ""

		mount /system 2>/dev/null
		mount /data 2>/dev/null
		if [ "`mount | grep data`" == "" ]; then
			echo "error: unable to mount /data, aborting"	
			exit 1
		fi
		if [ "`mount | grep system`" == "" ]; then
			echo "error: unable to mount /system, aborting"	
			exit 1
		fi
		
		CWD=$PWD
		cd $RESTOREPATH

                DEFAULTEXT=""
                if [ `ls *.bz2 2>/dev/null|wc -l` -ge 1 ]; then
                    DEFAULTCOMPRESSOR=bzip2
                    DEFAULTDECOMPRESSOR=bunzip2
                    DEFAULTEXT=.bz2
                fi
                if [ `ls *.gz 2>/dev/null|wc -l` -ge 1 ]; then
                    DEFAULTCOMPRESSOR=gzip
                    DEFAULTDECOMPRESSOR=gunzip
                    DEFAULTEXT=.gz
                fi

		if [ ! -f $RESTOREPATH/nandroid.md5$DEFAULTEXT ]; then
			echo "error: $RESTOREPATH/nandroid.md5 not found, cannot verify backup data"
			exit 1
		fi

                if [ `ls *.bz2 2>/dev/null|wc -l` -ge 1 -o `ls *.gz 2>/dev/null|wc -l` -ge 1 ]; then
                    echo "This backup is compressed with $DEFAULTCOMPRESSOR."

                    # Make sure that $DEFAULT[DE]COMPRESSOR exists
                    if [ `busybox | grep $DEFAULTCOMPRESSOR | wc -l` -le 0 -a\
                            `busybox | grep $DEFAULTDECOMPRESSOR | wc -l` -le 0 ]; then

                        echo "You do not have either the $DEFAULTCOMPRESSOR or the $DEFAULTDECOMPRESSOR"
                        echo "to unpack this backup, cleaning up and aborting!"
                        umount /system 2>/dev/null
                        umount /data 2>/dev/null
                        umount /sdcard 2>/dev/null
                        exit 1
                    fi
                    echo "Checking free space /sdcard for the decompression operation."
                    FREEBLOCKS="`df -k /sdcard| grep sdcard | awk '{ print $4 }'`"
                    # we need about 100MB for gzip to uncompress the files
                    if [ $FREEBLOCKS -le 100000 ]; then
                        echo "Error: not enough free space available on sdcard (need about 100mb)"
                        echo "to perform restore from the compressed images, aborting."
                        umount /system 2>/dev/null
                        umount /data 2>/dev/null
                        umount /sdcard 2>/dev/null
                        exit 1
                    fi
                    echo "Decompressing images, please wait...."
                    echo ""
                    # Starting from the largest while we still have more space to reduce
                    # space requirements
                    $DEFAULTCOMPRESSOR -d `ls -S *$DEFAULTEXT`
                    echo "Backup images decompressed"
                    echo ""
                fi

		echo "Verifying backup images..."
		md5sum -c nandroid.md5
		if [ $? -eq 1 ]; then
			echo "Error: md5sum mismatch, aborting"
			exit 1
		fi

                if [ `ls boot* 2>/dev/null | wc -l` == 0 ]; then
                    NOBOOT=1
                fi
                if [ `ls recovery* 2>/dev/null | wc -l` == 0 ]; then
                    NORECOVERY=1
                fi
                if [ `ls data* 2>/dev/null | wc -l` == 0 ]; then
                    NODATA=1
                fi
                if [ `ls system* 2>/dev/null | wc -l` == 0 ]; then
                    NOSYSTEM=1
                fi

		for image in boot recovery; do
                    if [ "$NOBOOT" == "1" -a "$image" == "boot" ]; then
                        echo ""
                        echo "Not flashing boot image!"
                        echo ""
                        continue
                    fi
                    if [ "$NORECOVERY" == "1" -a "$image" == "recovery" ]; then
                        echo ""
                        echo "Not flashing recovery image!"
                        echo ""
                        continue
                    fi
                    echo "Flashing $image..."
		    $flash_image $image $image.img
                done

		for image in data system; do
                        if [ "$NODATA" == "1" -a "$image" == "data" ]; then
                            echo ""
                            echo "Not restoring data image!"
                            echo ""
                            continue
                        fi
                        if [ "$NOSYSTEM" == "1" -a "$image" == "system" ]; then
                            echo ""
                            echo "Not restoring system image!"
                            echo ""
                            continue
                        fi
			echo "Erasing /$image..."
			cd /$image
			rm -rf * 2>/dev/null
			echo "Unpacking $image image..."
			$unyaffs $RESTOREPATH/$image.img
			cd /
			sync
			umount /$image
		done
		
		echo "Restore done"
		exit 0
fi

# 2.
if [ "$BACKUP" == 1 ]; then
echo "mounting system and data read-only, sdcard read-write"
umount /system 2>/dev/null
umount /data 2>/dev/null
umount /sdcard 2>/dev/null
mount -o ro /system || FAIL=1
mount -o ro /data || FAIL=2
mount /sdcard || mount /dev/block/mmcblk0 /sdcard || FAIL=3
case $FAIL in
	1) echo "Error mounting system read-only"; umount /system /data /sdcard; exit 1;;
	2) echo "Error mounting data read-only"; umount /system /data /sdcard; exit 1;;
	3) echo "Error mounting sdcard read-write"; umount /system /data /sdcard; exit 1;;
esac

if [ ! "$SUBNAME" == "" ]; then
    SUBNAME=$SUBNAME-
fi

# Identify the backup with what partitions have been backed up
if [ "$NOCACHE" == 0 ]; then
    BACKUPLEGEND=$BACKUPLEGEND"C"
fi
if [ "$NOBOOT" == 0 ]; then
    BACKUPLEGEND=$BACKUPLEGEND"B"
fi
if [ "$NODATA" == 0 ]; then
    BACKUPLEGEND=$BACKUPLEGEND"D"
fi
if [ "$NOMISC" == 0 ]; then
    BACKUPLEGEND=$BACKUPLEGEND"M"
fi
if [ "$NORECOVERY" == 0 ]; then
    BACKUPLEGEND=$BACKUPLEGEND"R"
fi
if [ "$NOSYSTEM" == 0 ]; then
    BACKUPLEGEND=$BACKUPLEGEND"S"
fi
if [ "$NOSPLASH1" == 0 ]; then
    BACKUPLEGEND=$BACKUPLEGEND"1"
fi
if [ "$NOSPLASH2" == 0 ]; then
    BACKUPLEGEND=$BACKUPLEGEND"2"
fi

if [ ! "$BACKUPLEGEND" == "" ]; then
    BACKUPLEGEND=$BACKUPLEGEND-
fi


TIMESTAMP="`date +%Y%m%d-%H%M`"
DESTDIR="$BACKUPPATH/$SUBNAME$BACKUPLEGEND$TIMESTAMP"
if [ ! -d $DESTDIR ]; then 
	mkdir -p $DESTDIR
	if [ ! -d $DESTDIR ]; then 
		echo "error: cannot create $DESTDIR"
		umount /system 2>/dev/null
		umount /data 2>/dev/null
		umount /sdcard 2>/dev/null
		exit 1
	fi
else
	touch $DESTDIR/.nandroidwritable
	if [ ! -e $DESTDIR/.nandroidwritable ]; then
		echo "error: cannot write to $DESTDIR"
		umount /system 2>/dev/null
		umount /data 2>/dev/null
		umount /sdcard 2>/dev/null
		exit 1
	fi
	rm $DESTDIR/.nandroidwritable
fi

# 3.
echo "checking free space on sdcard"
FREEBLOCKS="`df -k /sdcard| grep sdcard | awk '{ print $4 }'`"
# we need about 130MB for the dump
if [ $FREEBLOCKS -le 130000 ]; then
	echo "error: not enough free space available on sdcard (need 130mb), aborting."
	umount /system 2>/dev/null
	umount /data 2>/dev/null
	umount /sdcard 2>/dev/null
	exit 1
fi



if [ -e /dev/mtd/mtd6ro ]; then
    if [ "$NOSPLASH1" == 0 ]; then
	echo -n "Dumping splash1 from device over tcp to $DESTDIR/splash1.img..."
	dd if=/dev/mtd/mtd6ro of=$DESTDIR/splash1.img skip=19072 bs=2048 count=150 2>/dev/null
	echo "done"
	sleep 1s
    else
        echo "Dump of the splash1 image suppressed."
    fi
    if [ "$NOSPLASH2" == 0 ]; then
	echo -n "Dumping splash2 from device over tcp to $DESTDIR/splash2.img..."
	dd if=/dev/mtd/mtd6ro of=$DESTDIR/splash2.img skip=19456 bs=2048 count=150 2>/dev/null
	echo "done"
    else
        echo "Dump of the splash2 image suppressed."
    fi
fi


# 5.
for image in boot recovery misc; do

    case $image in
        boot)
            if [ "$NOBOOT" == 1 ]; then
                echo "Dump of the boot partition suppressed."
                continue
            fi
            ;;
        recovery)
            if [ "$NORECOVERY" == 1 ]; then
                echo "Dump of the recovery partition suppressed."
                continue
            fi
            ;;
        misc)
            if [ "$NOMISC" == 1 ]; then
                echo "Dump of the misc partition suppressed."
                continue
            fi
            ;;
    esac

	# 5a
	DEVICEMD5=`$dump_image $image - | md5sum | awk '{ print $1 }'`
	sleep 1s
	MD5RESULT=1
	# 5b
	echo -n "Dumping $image to $DESTDIR/$image.img..."
	ATTEMPT=0
	while [ $MD5RESULT -eq 1 ]; do
		let ATTEMPT=$ATTEMPT+1
		# 5b1
		$dump_image $image $DESTDIR/$image.img 
		sync
		# 5b3
		echo "${DEVICEMD5}  $DESTDIR/$image.img" | md5sum -c -s -
		if [ $? -eq 1 ]; then
			true
		else
			MD5RESULT=0
		fi
		if [ "$ATTEMPT" == "5" ]; then
			echo "fatal error while trying to dump $image, aborting"
			umount /system
			umount /data
			umount /sdcard
			exit 1
		fi
	done
	echo "done"
done

# 6
for image in system data cache; do
    case $image in
        system)
            if [ "$NOSYSTEM" == 1 ]; then
                echo "Dump of the system partition suppressed."
                continue
            fi
            ;;
        data)
            if [ "$NODATA" == 1 ]; then
                echo "Dump of the data partition suppressed."
                continue
            fi
            ;;
        cache)
            if [ "$NOCACHE" == 1 ]; then
                echo "Dump of the cache partition suppressed."
                continue
            fi
            ;;
    esac

	# 6a
	echo -n "Dumping $image to $DESTDIR/$image.img..."
	$mkyaffs2image /$image $DESTDIR/$image.img
	sync
	echo "done"
done


# 7.
echo -n "generating md5sum file..."
CWD=$PWD
cd $DESTDIR
md5sum *img > nandroid.md5

# 7b.
if [ "$COMPRESS" == 1 ]; then
    echo "Compressing the backup, may take a bit of time, please wait..."
    echo "checking free space on sdcard for the compression operation."
    FREEBLOCKS="`df -k /sdcard| grep sdcard | awk '{ print $4 }'`"
    # we need about 70MB for the intermediate storage needs
    if [ $FREEBLOCKS -le 70000 ]; then
	echo "error: not enough free space available on sdcard for compression operation (need 70mb)"
        echo "leaving this backup uncompressed."
    else
        # we are already in $DESTDIR, start compression from the smallest files
        # to maximize space for the largest's compression, less likely to fail.
        # To decompress reverse the order.
        $DEFAULTCOMPRESSOR $DEFAULTLEVEL `ls -S -r *`
    fi
fi

cd $CWD
echo "done"

# 8.
echo "unmounting system, data and sdcard"
umount /system
umount /data
umount /sdcard

# 9.
echo "Backup successful."
if [ "$AUTOREBOOT" == 1 ]; then
    reboot
fi
exit 0
fi


# ----------------------------------GETTING UPDATES DIRECT FROM THE WEB USING WIFI-------------

if [ "$WEBGET" == 1 ]; then
    echo "mounting system and data read-only, sdcard read-write"
    umount /system 2>/dev/null
    umount /data 2>/dev/null
    umount /sdcard 2>/dev/null

    # Since we are in recovery, these file-systems have to be mounted
    echo "Mounting /system and /data for starting WiFi"
    mount -o ro /system || FAIL=1
    # Need to write to this system to setup nameservers for the wifi
    mount -o rw /data || FAIL=2
    mount /sdcard || mount /dev/block/mmcblk0 /sdcard || FAIL=3

    case $FAIL in
	1) echo "Error mounting system read-only"; umount /system /data /sdcard; exit 1;;
	2) echo "Error mounting data read-write"; umount /system /data /sdcard; exit 1;;
	3) echo "Error mounting sdcard read-write"; umount /system /data /sdcard; exit 1;;
    esac

    if [ "$WEBGETSOURCE" == "" ]; then 
        # Set the URL to the current latest update
        if [ "$ITSANUPDATE" == 1 ]; then
            WEBGETSOURCE=$DEFAULTWEBUPDATE
        else
            WEBGETSOURCE=$DEFAULTWEBIMAGE
        fi
    fi

    if [ "$AUTOAPPLY" == 0 ]; then
        # Need to check space on sdcard only if we dump the update there.
        echo "Checking free space on sdcard for the update download."
        FREEBLOCKS="`df -k /sdcard| grep sdcard | awk '{ print $4 }'`"
        # we need about 50MB for the storage needs
        if [ $FREEBLOCKS -le 50000 ]; then
            echo "Error: not enough free space available on sdcard for the update operation (need 50mb)"
            echo "Please free up space before invoking this option again."
            echo "Cleaning up, unmounting file systems, aborting."
            umount /system /data /sdcard
            exit 1
        fi
    fi

    if [ ! `basename $WEBGETSOURCE` == `basename $WEBGETSOURCE .zip` ]; then
        # It is a zip, not img.
        ITSANUPDATE=1
    else
        if [ ! `basename $WEBGETSOURCE` == `basename $WEBGETSOURCE .img` ]; then
           # It is an img file.
           ITSANIMAGE=1
        else
            # Unknown file type
            echo "Unknown file type, cleaning up, aborting."
            umount /system /data /sdcard
            exit 1
        fi
    fi


    if [ "$ITSANUPDATE" == 1 -a "$AUTOAPPLY" == 0 ]; then
         # Move the previous update aside, if things go badly with the new update, it is good
         # to have the last one still around :-)

         # If we cannot figure out what the file name used to be, create this new one with a time stamp
        OLDNAME="OLD-update-`date +%Y%m%d-%H%M`"

        if [ -e $WEBGETTARGET/update.zip ]; then
            echo "There is already an update.zip in $WEBGETTARGET, backing it up to"
            if [ -e $WEBGETTARGET/update.name ]; then
                OLDNAME=`cat $WEBGETTARGET/update.name`
                # Backup the name file (presumably contains the old name of the update.zip
                mv -f $WEBGETTARGET/update.name $WEBGETTARGET/`basename $OLDNAME .zip`.name
            fi
            echo "`basename $OLDNAME .zip`.zip"
            mv -f $WEBGETTARGET/update.zip $WEBGETTARGET/`basename $OLDNAME .zip`.zip

            # Backup the MD5sum file
            if [ -e $WEBGETTARGET/update.MD5sum ]; then
                mv -f $WEBGETTARGET/update.MD5sum $WEBGETTARGET/`basename $OLDNAME .zip`.MD5sum
            fi
        fi
    fi

    echo "Starting WiFI, please wait..."
    insmod /system/lib/modules/wlan.ko

    wlan_loader -f /system/etc/wifi/Fw1251r1c.bin -e /proc/calibration -i /system/etc/wifi/tiwlan.ini

    CWD=`pwd`
    cd /data/local/tmp

    wpa_supplicant -f -Dtiwlan0 -itiwlan0 -c/data/misc/wifi/wpa_supplicant.conf&

    sleep 5
    echo "wpa_supplicant started"
    echo ""

    echo "nameserver $NAMESERVER1" >/etc/resolv.conf
    echo "nameserver $NAMESERVER2" >>/etc/resolv.conf

    #We want the wifi to assign a dynamic address
    echo "Starting DHCPCD server (dynamic address assignment)"
    # -BKL flags????
    dhcpcd -d tiwlan0 2>/dev/null &

    # Have to wait for it to init stuff
    sleep 10


    CHECK1=`ps | grep -v grep | grep dhcpcd`
    CHECK2=`ps | grep -v grep | grep wpa_supplicant`
    if [ "$CHECK1" == "" -o "$CHECK2" == "" ]; then
         echo "Error: wpa_supplicant or DHCPCD server is not running, cleaning up, aborting"
         rm -- -Dtiwlan0
         cd $CWD

         echo "unmounting /system, /data and /sdcard"
         umount /system
         umount /data
         umount /sdcard
         exit 2
    fi

    echo "DHCPCD server started"
    echo ""

    echo "WiFi is running!"
    echo ""

    if [ "$AUTOAPPLY" == 1 ]; then
        echo "Autoapply is on, retrieving the update into /cache/`basename $WEBGETSOURCE`"

        wget -O /cache/`basename $WEBGETSOURCE` $WEBGETSOURCE

        if [ ! -e /cache/recovery ]; then
            mkdir /cache/recovery
            chmod 777 /cache/recovery
        fi
        if [ -e /cache/recovery/command ]; then
            echo "--update_package=CACHE:`basename $WEBGETSOURCE`" >>/cache/recovery/command
        else
            echo "--update_package=CACHE:`basename $WEBGETSOURCE`" >/cache/recovery/command
        fi
        chmod 555 /cache/recovery/command
        # Once rebooted the update will be applied.

    else

        if [ "$ITSANUPDATE" == 1 ]; then
            echo "Retrieving system update into $WEBGETTARGET/update.zip, please wait..."
            wget -O $WEBGETTARGET/update.zip $WEBGETSOURCE

            echo "`basename $WEBGETSOURCE`" > $WEBGETTARGET/update.name
            echo ""
            echo "Update retrieved, if concerned, please compare the md5sum with the number"
            echo "you see on the web page, if it is NOT the same, the retrieval"
            echo "has failed and has to be repeated."
            echo ""
            echo `md5sum $WEBGETTARGET/update.zip | tee $WEBGETTARGET/update.MD5sum`
            echo ""
            echo "MD5sum has been stored in $WEBGETTARGET/update.MD5sum"
        else
            echo "Retrieving the image into $WEBGETTARGET/`basename $WEBGETSOURCE`, please wait..."
            wget -O $WEBGETTARGET/`basename $WEBGETSOURCE` $WEBGETSOURCE
            echo ""
            echo "$WEBGETSOURCE retrieved, if concerned, please compare the md5sum with the number"
            echo "you see on the web page, if it is NOT the same, the retrieval"
            echo "has failed and has to be repeated."
            echo ""
            md5sum $WEBGETTARGET/`basename $WEBGETSOURCE` | tee $WEBGETTARGET/`basename $WEBGETSOURCE .img`.MD5sum
            echo ""
            echo "MD5sum has been stored in $WEBGETTARGET/`basename $WEBGETSOURCE .img`.MD5sum"
            echo ""
            echo -n "Would you like to flash this image into boot or recovery? (or no for no flash) "
            read ANSWER
            if [ "$ANSWER" == "boot" ]; then
                 echo "Flashing $WEBGETTARGET/`basename $WEBGETSOURCE` into the boot partition."
                $flash_image boot $WEBGETTARGET/`basename $WEBGETSOURCE`
            else
                if [ "$ANSWER" == "recovery" ]; then
                    echo "Moving $WEBGETTARGET/`basename $WEBGETSOURCE` into the /data/recovery.img"
                    echo "and /system/recovery.img"
                    cp -f $WEBGETTARGET/`basename $WEBGETSOURCE` /data/recovery.img
                    mount -o rw,remount /system
                    cp -f $WEBGETTARGET/`basename $WEBGETSOURCE` /system/recovery.img
                    echo "Depending on the settings of your specific ROM, the recovery.img will be"
                    echo "flashed at the normal bootup time either from /system or /data."
                else
                    echo "Not flashing the image."
                fi
            fi
        fi
        echo ""

    fi

    echo "Shutting down DHCPCD service and wpa_supplicant"
    killall -TERM dhcpcd
    TEMPVAR=`ps | grep -v grep | grep wpa_supplicant`
    TEMPVAR=`echo $TEMPVAR | cut -f 1 -d ' '`
    kill -TERM $TEMPVAR

    while true; do
        CHECK=`ps | grep -v grep | grep dhcpcd`
        if [ ! "$CHECK" == "" ]; then
            sleep 1
        else
            break
        fi
    done

    while true; do
        CHECK=`ps | grep -v grep | grep wpa_supplicant`
        if [ ! "$CHECK" == "" ]; then
            sleep 1
        else
            break
        fi
    done
    #sleep 5

    echo "Cleaning up..."
    # Looks like cannot clean up wlan module since chdir is missing
    #rmmod wlan
    rm -- -Dtiwlan0
    cd $CWD

    echo "unmounting /system, /data and /sdcard"
    umount /system
    umount /data
    umount /sdcard

    if [ "$AUTOAPPLY" == 1 ]; then
        echo "Auto apply update is on, rebooting into recovery to apply the update."
        echo "When the update is complete reboot into the normal mode."
        echo "The device will reboot and the update will be applied in 10 seconds!"
        sleep 10
        reboot recovery
    else
        if [ "$ITSANUPDATE" == 1 ]; then
            echo "If you put the update into a folder other than /sdcard you need to use --getupdate to"
            echo "prepare the update for application."
            echo "You may want to execute 'reboot recovery' and choose update option to flash the update."
            echo "Or in the alternative, shutdown your phone with reboot -p, and then press <CAMERA>+<POWER>"
            echo "to initiate a normal system update procedure, if you have stock SPL."
        fi
        exit 0
    fi
fi

# -------------------------------------DELETION, COMPRESSION OF BACKUPS---------------------------------
if [ "$COMPRESS" == 1 -o "$DELETE" == 1 ]; then
    echo "Unmounting /system and /data to be on the safe side, mounting /sdcard read-write."
    umount /system 2>/dev/null
    umount /data 2>/dev/null
    umount /sdcard 2>/dev/null

    FAIL=0
    # Since we are in recovery, these file-system have to be mounted
    echo "Mounting /sdcard to look for backups."
    mount /sdcard || mount /dev/block/mmcblk0 /sdcard || FAIL=1

    if [ "$FAIL" == 1 ]; then
	echo "Error mounting /sdcard read-write, cleaning up..."; umount /system /data /sdcard; exit 1
    fi

    echo "The current size of /sdcard FAT32 filesystem is `du /sdcard | tail -1 | cut -f 1 -d '/'`Kb"
    echo ""

    # find the oldest backup, but show the user other options
    echo "Looking for the oldest backup to delete, newest to compress,"
    echo "will display all choices!"
    echo ""
    echo "Here are the backups you have picked within this repository $BACKUPPATH:"

    if [ "$DELETE" == 1 ]; then
        RESTOREPATH=`ls -td $BACKUPPATH/*$SUBNAME* 2>/dev/null | tail -1`
        ls -td $BACKUPPATH/*$SUBNAME* 2>/dev/null
    else
        RESTOREPATH=`ls -trd $BACKUPPATH/*$SUBNAME* 2>/dev/null | tail -1`
        ls -trd $BACKUPPATH/*$SUBNAME* 2>/dev/null
    fi
    echo " "

    if [ "$RESTOREPATH" = "" ];	then
	echo "Error: no backups found"
	    exit 2
	else
            if [ "$DELETE" == 1 ]; then
                echo "Default backup to delete is the oldest: $RESTOREPATH"
                echo ""
                echo "Other candidates for deletion are: "
                ls -td $BACKUPPATH/*$SUBNAME* 2>/dev/null | grep -v $RESTOREPATH
            fi
            if [ "$COMPRESS" == 1 ]; then
                echo "Default backup to compress is the latest: $RESTOREPATH"
                echo ""
                echo "Other candidates for compression are: "
                ls -trd $BACKUPPATH/*$SUBNAME* 2>/dev/null | grep -v $RESTOREPATH
            fi

            echo ""
            echo "Using G1 keyboard, enter a unique name substring to change it and <CR>"
            echo -n "or just <CR> to accept: "
            if [ "$ASSUMEDEFAULTUSERINPUT" == 0 ]; then
                 read SUBSTRING
            else
                echo "Accepting default."
                SUBSTRING=""
            fi

            if [ ! "$SUBSTRING" == "" ]; then
                 RESTOREPATH=`ls -td $BACKUPPATH/*$SUBNAME* 2>/dev/null | grep $SUBSTRING | tail -1`
            else
                 RESTOREPATH=`ls -td $BACKUPPATH/*$SUBNAME* 2>/dev/null | tail -1`
            fi
            if [ "$RESTOREPATH" = "" ]; then
                 echo "Error: no matching backup found, aborting"
                 exit 2
            fi
     fi
		
     if [ "$DELETE" == 1 ]; then
         echo "Deletion path: $RESTOREPATH"
         echo ""
         echo "WARNING: Deletion of a backup is an IRREVERSIBLE action!!!"
         echo -n "Are you absolutely sure? {yes | YES | Yes | no | NO | No}: "
         if [ "$ASSUMEDEFAULTUSERINPUT" == 0 ]; then
             read ANSWER
         else
             ANSWER=yes
             echo "Accepting default."
         fi
         echo ""
         if [ "$ANSWER" == "yes" -o "$ANSWER" == "YES" -o "$ANSWER" == "Yes" ]; then
             rm -rf $RESTOREPATH
             echo ""
             echo "$RESTOREPATH has been permanently removed from your SDCARD."
             echo "Post deletion size of the /sdcard FAT32 filesystem is `du /sdcard | tail -1 | cut -f 1 -d '/'`Kb"
         else 
             if [ "$ANSWER" == "no" -o "$ANSWER" == "NO" -o "$ANSWER" == "No" ]; then
                 echo "The chosen backup will NOT be removed."
             else 
                 echo "Invalid answer: assuming NO."
             fi
         fi
     fi

     if [ "$COMPRESS" == 1 ]; then
         
         CWD=`pwd`
         cd $RESTOREPATH

         if [ `ls *.bz2 2>/dev/null|wc -l` -ge 1 -o `ls *.gz 2>/dev/null|wc -l` -ge 1 ]; then
             echo "This backup is already compressed, cleaning up, aborting..."
             cd $CWD
             umount /sdcard 2>/dev/null
             exit 0
         fi

         echo "checking free space on sdcard for the compression operation."
         FREEBLOCKS="`df -k /sdcard| grep sdcard | awk '{ print $4 }'`"
         # we need about 70MB for the intermediate storage needs
         if [ $FREEBLOCKS -le 70000 ]; then
             echo "Error: not enough free space available on sdcard for compression operation (need 70mb)"
             echo "leaving this backup uncompressed."
         else
             # we are already in $DESTDIR, start compression from the smallest files
             # to maximize space for the largest's compression, less likely to fail.
             # To decompress reverse the order.
             echo "Pre compression size of the /sdcard FAT32 filesystem is `du /sdcard | tail -1 | cut -f 1 -d '/'`Kb"
             echo ""
             echo "Compressing the backup may take a bit of time, please wait..."
             $DEFAULTCOMPRESSOR $DEFAULTLEVEL `ls -S -r *`
             echo ""
             echo "Post compression size of the /sdcard FAT32 filesystem is `du /sdcard | tail -1 | cut -f 1 -d '/'`Kb"
         fi
     fi

     echo "Cleaning up."
     cd $CWD
     umount /sdcard 2>/dev/null
     exit 0

fi

if [ "$GETUPDATE" == 1 ]; then
    echo "Unmounting /system and /data to be on the safe side, mounting /sdcard read-write."
    umount /system 2>/dev/null
    umount /data 2>/dev/null
    umount /sdcard 2>/dev/null

    FAIL=0
    # Since we are in recovery, these file-system have to be mounted
    echo "Mounting /sdcard to look for updates to flash."
    mount /sdcard || mount /dev/block/mmcblk0 /sdcard || FAIL=1

    if [ "$FAIL" == 1 ]; then
	echo "Error mounting /sdcard read-write, cleaning up..."; umount /system /data /sdcard; exit 1
    fi

    echo "The current size of /sdcard FAT32 filesystem is `du /sdcard | tail -1 | cut -f 1 -d '/'`Kb"
    echo ""

    # find all the files with update in them, but show the user other options
    echo "Looking for all *update*.zip candidate files to flash."
    echo ""
    echo "Here are the updates limited by the subname $SUBNAME found"
    echo "within the repository $DEFAULTUPDATEPATH:"
    echo ""
    RESTOREPATH=`ls -trd $DEFAULTUPDATEPATH/*$SUBNAME*.zip 2>/dev/null | grep update | tail -1`
    if [ "$RESTOREPATH" == "" ]; then
        echo "Error: found no matching updates, cleaning up, aborting..."
        umount /sdcard 2>/dev/null
        exit 2
    fi
    ls -trd $DEFAULTUPDATEPATH/*$SUBNAME*.zip 2>/dev/null | grep update
    echo ""
    echo "The default update is the latest $RESTOREPATH"
    echo ""
    echo "Using G1 keyboard, enter a unique name substring to change it and <CR>"
    echo -n "or just <CR> to accept: "
    if [ "$ASSUMEDEFAULTUSERINPUT" == 0 ]; then
         read SUBSTRING
    else
         echo "Accepting default."
         SUBSTRING=""
    fi
    echo ""

    if [ ! "$SUBSTRING" == "" ]; then
          RESTOREPATH=`ls -trd $DEFAULTUPDATEPATH/*$SUBNAME*.zip 2>/dev/null | grep update | grep $SUBSTRING | tail -1`
    else
          RESTOREPATH=`ls -trd $DEFAULTUPDATEPATH/*$SUBNAME*.zip 2>/dev/null | grep update | tail -1`
    fi
    if [ "$RESTOREPATH" = "" ]; then
          echo "Error: no matching backups found, aborting"
          exit 2
    fi

    if [ "$RESTOREPATH" == "/sdcard/update.zip" ]; then
        echo "You chose update.zip, it is ready for flashing, there nothing to do."
    else

        # Things seem ok so far.

        # Move the previous update aside, if things go badly with the new update, it is good
        # have the last one still around :-)

        # If we cannot figure out what the file name used to be, create this new one with a time stamp
        OLDNAME="OLD-update-`date +%Y%m%d-%H%M`"

        if [ -e /sdcard/update.zip ]; then
            echo "There is already an update.zip in /sdcard, backing it up to"
            if [ -e /sdcard/update.name ]; then
                OLDNAME=`cat /sdcard/update.name`
                # Backup the name file (presumably contains the old name of the update.zip
                mv -f /sdcard/update.name /sdcard/`basename $OLDNAME .zip`.name
            fi
            echo "`basename $OLDNAME .zip`.zip"
            mv -f /sdcard/update.zip /sdcard/`basename $OLDNAME .zip`.zip

            # Backup the MD5sum file
            if [ -e /sdcard/update.MD5sum ]; then
                mv -f /sdcard/update.MD5sum /sdcard/`basename $OLDNAME .zip`.MD5sum
            fi
        fi

        if [ -e $DEFAULTUPDATEPATH/`basename $RESTOREPATH .zip`.MD5sum ]; then
            mv -f $DEFAULTUPDATEPATH/`basename $RESTOREPATH .zip`.MD5sum /sdcard/update.MD5sum
        else
            echo `md5sum $RESTOREPATH | tee /sdcard/update.MD5sum`
            echo ""
            echo "MD5sum has been stored in /sdcard/update.MD5sum"
            echo ""
        fi
        if [ -e $DEFAULTUPDATEPATH/`basename $RESTOREPATH .zip`.name ]; then
            mv -f $DEFAULTUPDATEPATH/`basename $RESTOREPATH .zip`.name /sdcard/update.name
        else
            echo "`basename $RESTOREPATH`" > /sdcard/update.name
        fi

        mv -i $RESTOREPATH /sdcard/update.zip


        echo "Your file $RESTOREPATH has been moved to the root of sdcard, and is ready for flashing!!!"

    fi

    echo "You may want to execute 'reboot recovery' and then choose the update option to flash the update."
    echo "Or in the alternative, shutdown your phone with reboot -p, and then press <CAMERA>+<POWER> to"
    echo "initiate a standard update procedure."
    echo ""
    echo "Cleaning up and exiting."
    umount /sdcard 2>/dev/null
    exit 0
fi
