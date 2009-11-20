#!/sbin/sh
mount /sdcard 2>/dev/null
echo "++ mounting system"
mount /system 2>/dev/null
echo "++ changing directories"
cd /system
echo "++ checking for image"
	if [ -e "/sdcard/system-$1.img" ]; then
		echo "++ deleting data in /system"
		rm -rf * 2>/dev/null
		echo "++ unpacking system.img image"
		/sbin/unyaffs /sdcard/system-$1.img
		echo "++ changing directories"
		cd /
		echo "++ syncing"
	else
		echo "!! restore failed"
		sync
		sh /sbin/mnt_toggle 0
		exit 1
	fi
sync
sh /sbin/demount
exit 0
