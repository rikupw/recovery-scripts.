#!/sbin/sh
##########
#This script is my personal initial script file for after my updates into (specifically) cyanogen's AOSP builds!
#for questions please email:  rikupw@gmail.com
#######
fontscript=ubuntufont.sh
####################
# GLOBAL VARIABLES #
####################
fix_ver="2.03"
symlink=0
fix_per=0
audiosh=0
manpage=0
dataopt=0
sdc_set=0
fstabup=0
changed=0
rm_sam2=0
metamrf=0
fontset=0
zip_all=0
####################
#	script	    #
####################
if [ ! -e /dev/block/mmcblk0p2 ]; then
	exit
else
	/sbin/mnt_toggle 0
	echo
######################################################
#	Set 4th partition into system, if exist	        #
######################################################
	if [ -e /dev/block/mmcblk0p4 ]; then
		mount /system > /dev/null 2>&1;
		if [ ! -d /system/sdc ]; then
			mkdir /system/sdc
			touch /system/sdc/placeholder
			sdc_set=1
			changed=1
		fi
		if [ "$(grep '0p4' /system/etc/fstab | awk '{print $2}')"0 = ""0 ]; then
			echo "/dev/block/mmcblk0p4	/system/sdc	auto	rw">>/system/etc/fstab
			fstabup=1
			changed=1
		else
			fstabup=0
		fi
		sh /sbin/mnt_toggle 1 > /dev/null 2>&1;
	else
		sh /sbin/mnt_toggle 1 > /dev/null 2>&1;
		fstabup=0
		sdc_set=0
	fi
######################################################
#	Link secondary bin directories to path	        #
######################################################
	if [ -e /system/sd/bin ]; then
            [ ! -d /data/local ] && mkdir /data/local
		if [ ! -s /data/local/bin ]; then
			busybox ln -s /system/sd/bin /data/local/bin
			symlink=1
			changed=1
		else
			symlink=0
		fi
	elif [ ! -e /dev/block/mmcblk0p2 ]; then
            [ ! -d /data/local ] && mkdir /data/local
            if [ -s /data/local/bin ]; then
                  rm /data/local/bin
                  mkdir /data/local/bin
                  symlink=2
			changed=1
            fi
	fi
######################################################
#	If $1 is 1 then execute fonts			        #
######################################################
	if [ ! -e /system/fonts/.font ]; then
		sh /system/sd/etc/fonts/$fontscript
		fontset=1
		changed=1
	else
		fontset=0
	fi
######################################################
#	Install personal audio files ;)		        #
######################################################
	if [ ! -e /system/media/audio/audio.sh ]; then
		if [ -e /system/sd/etc/audio/audio.sh ]; then
			sh /system/sd/etc/audio/audio.sh
			audiosh=1
			changed=1
		else
			changed=1
			audiosh=2
            fi
	else
		audiosh=0
	fi
######################################################
#	Install Man docs						   #
######################################################
	if [ ! -d /system/usr/share/man ]; then
		sh /system/sd/etc/manpages/man_install
		manpage=1
		changed=1
	else
		manpage=0
	fi
######################################################
#	Setup /data/opt for Autostart app, if wanted	   #
######################################################
	if [ ! -e /data/opt/.placeholder ]; then
		mkdir /data/opt
		echo "0">/data/opt/.placeholder
		dataopt=1
		changed=1
	else
		dataopt=0
	fi
######################################################
#	Fix Permissions update					   #
######################################################
	if [ "$(sh /system/bin/fix_permissions -V | awk '{print $2}')" != "$fix_ver" ]; then
		cp /system/sd/etc/fix_perm/fix_permissions /system/bin/fix_permissions
		chmod 0755 /system/bin/fix_permissions
		fix_per=1
		changed=1
	else
		fix_per=0
	fi
######################################################
#	Remove sam2.apk (i download on my own)	        #
######################################################
	if [ -e /data/app/sam2.apk ]; then
		rm -rf /data/app/sam2.apk;
		rm -rf /system/sd/app/sam2.apk;
		rm_sam2=1
		changed=1
	else
		rm_sam2=0
	fi
######################################################
#	Install Metamorph.sh and zip binary		   #
######################################################
	if [ -e /system/bin/zip ]; then
		metamrf=0
	else
		cp /system/sd/etc/metamorph/zip /system/bin/zip
		chmod 755 /system/bin/zip
		cp /system/sd/etc/metamorph/mm.sh /system/bin/metamorph.sh
		chmod 755 /system/bin/metamorph.sh
		metamrf=1
		changed=1
	fi
######################################################
#	Install Zipalign+script					   #
######################################################
	#	if [ -e /system/bin/zipall.sh ]; then
	#		zip_all=0
	#	else
	#		if [ ! -e /system/bin/zipalign ]; then
	#			cp /system/sd/etc/zip-arm/zipalign /system/bin/zipalign
	#			chmod 755 /system/bin/zipalign
	#		fi
	#		cp /system/sd/etc/zip-arm/zipall-arm.sh /system/bin/zipall.sh
	#		chmod 755 /system/bin/zipall.sh
	#		zip_all=1
	#		changed=1
	#	fi
######################################################
#	backup /system/sd/etc//bin			        #
######################################################
	#	[ ! -d /sdcard/etc/sd ] && mkdir /sdcard/etc/sd
	#	if [ -d /system/sd/bin ]; then
	#		cd /system/sd
	#		if [ -e /sdcard/etc/sd/bin.tar ]; then
	#			mv /sdcard/etc/sd/bin.tar.gz /sdcard/etc/sd/bin.tar.gz-old
	#		fi
	#		tar -cz bin > /sdcard/etc/sd/bin.tar.gz 2>&1;
	#		bintard=1
	#		backup=1
	#		cd /
	#	else
	#		backup=0
	#		bintard=0
	#	fi
	#	if [ -d /system/sd/etc ]; then
	#		cd /system/sd
	#		if [ -e /sdcard/etc/sd/etc.tar.gz ]; then
	#			mv /sdcard/etc/sd/etc.tar.gz /sdcard/etc/sd/etc-bak.tar.gz-old
	#		fi
	#		tar -cz etc > /sdcard/etc/sd/etc.tar.gz 2>&1;
	#		etctard=1
	#		backup=1
	#		cd /
	#	else
	#		backup=0
	#		etctard=0
	#	fi
######################################################
#	tell me what I changed!				        #
######################################################
	if [ "$changed" -ne "0" ]; then
		echo "the following was changed:"
		[ "$symlink" -eq "1" ] && echo "+	data/local/bin linked to /system/sd/bin"
		[ "$sdc_set" -eq "1" ] && echo "+	/system/sdc created"
		[ "$fstabup" -eq "1" ] && echo "+	fstab updated for /dev/block/mmcblk0p4"
		[ "$audiosh" -eq "1" ] && echo "+	audio files copied"
		[ "$manpage" -eq "1" ] && echo "+	manpages installed"
		[ "$dataopt" -eq "1" ] && echo "+	/data/opt has been created"
		[ "$fix_per" -eq "1" ] && echo "+	fix_permisions is now the latest version: $fix_ver"
		[ "$rm_sam2" -eq "1" ] && echo "+	/data/app/sam2.apk has been removed"
		[ "$fontset" -eq "1" ] && echo "+	ubuntu titling fonts installed"
		[ "$metamrf" -eq "1" ] && echo "+	metamorph and zip has been installed"
#		[ "$zip_all" -eq "1" ] && echo "+	zipall and zipalign has been installed"
			[ "$symlink" -eq "2" ] && echo "! ! sd/bin -ne, created local/bin instead"
			[ "$sdc_set" -eq "2" ] && echo "! ! /system/sdc not needed"
			[ "$fstabup" -eq "2" ] && echo "! !	0p4 non-existant"
			[ "$audiosh" -eq "2" ] && echo "! !	audio.sh does not exist"
			[ "$manpage" -eq "2" ] && echo "! ! manpages not found"
#			[ "$dataopt" -eq "2" ]
#			[ "$fix_per" -eq "2" ]
#			[ "$rm_sam2" -eq "2" ]
#			[ "$fontset" -eq "2" ]
#			[ "$metamrf" -eq "2" ]
		if [ "$backdup" -eq "1" ]; then
			[ "$etc_tar" -eq "1" ] && echo "++ /system/sd/etc has been back'd up"
			[ "$bin_tar" -eq "1" ] && echo "++ /system/sd/bin has been back'd up"
		fi
	else
		echo "--	nothing to be done"
		/sbin/mnt_toggle 0 > /dev/null 2>&1;
		exit 1
	fi
	sync
	sleep 1
	/sbin/mnt_toggle 0 > /dev/null 2>&1;
	/sbin/demount
fi
exit 0
