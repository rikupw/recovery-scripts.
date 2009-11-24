#!/sbin/sh
mount /sdcard 2>/dev/null
echo "++ mounting system"
mount /system 2>/dev/null
echo "++ changing directories"
cd /system
echo "++ checking for image"
	if [ -e "/sdcard/system.img" ]; then
		echo "++ deleting data in /system"
		rm -rf * 2>/dev/null
		echo "++ unpacking system.img image"
		/sbin/unyaffs /sdcard/system.img
		echo "++ changing directories"
		cd /
		echo "++ syncing"
	else
		echo "!! restore failed"
		sync
		cd /
		sh /sbin/mnt_toggle 0
		exit 1
	fi
sync
sh /sbin/demount
exit 0
