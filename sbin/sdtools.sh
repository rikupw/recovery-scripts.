#!/sbin/sh
VER="v1.0"
UNIT="foo"
DSIZE="foo"
SIZE="foo"
NUM="foo"
BSEXT2="foo"
BSWAP="foo"

print_usage()
{
	echo "$0 $VER"
	echo ""
	echo "Usage: $0 [OPTION]..."
	echo ""
	echo "Options:"
	echo "          -h --help	Display this help"
	echo "          -p --print	Display SD partitions"
	echo "          -s --split	Create 500MB ext2, 32MD swap and fill remaining"
	echo "          		space with a fat32 partition"
	echo "          -c --clean	Create 1 fat32 partition"
	echo ""
}

do_exit()
{
	exit $1
}

if [ "$1" == "" ]; then
	print_usage
	do_exit 0
fi

case $1 in
	-h|--help)
		print_usage
	;;

	-p|--print)
		parted -s /dev/block/mmcblk0 print
	;;

	-c|--clean|-s|--split)

		if [ -e /dev/block/mmcblk0 ]
		then
		    umount /system/sd > /dev/null 2>&1
		fi

		NUM=`parted -s /dev/block/mmcblk0 print | tail -2 | cut -d " " -f 2`
		if [ "$NUM" == "" ]
  			then
				NUM=0
			fi

		while [ $NUM != 0 ]
		do
			parted -s /dev/block/mmcblk0 rm $NUM
			NUM=`expr $NUM - 1`
		done

		DSIZE=`parted -s /dev/block/mmcblk0 print | grep "Disk /dev/block/mmcblk0" | cut -f 3 -d " "`
		  	if [ "$DSIZE" == "" ]
  			then
  				echo "Error: Unable to get SDcard-size, try to clean first, aborting"
				do_exit 1
			fi

		case $1 in
			-c|--clean)
				parted -s /dev/block/mmcblk0 mkpartfs primary fat32 0 $DSIZE
				echo "SDcard cleaned (fat32)"
			;;

			-s|--split)

				UNIT=`echo $DSIZE | sed -e "s/[0-9]*\.*[0-9]*//"`
				if [ "$UNIT" != "MB" ]
				then
					if [ "$UNIT" != "GB" ]
					then
						echo "Error: Unknown unit, aborting"
						do_exit 1
					fi
				fi

  				SIZE=`echo $DSIZE |sed -e "s/[A-Z][A-Z]//"`
  				if [ "$SIZE" == "" ]
  				then
					echo "Error: Unable to get SDcard-size, aborting"
					do_exit 1
 				fi

				if [ "$UNIT" == "MB" ]
				then
					BSWAP=`expr $SIZE - 32`
					BSEXT2=`expr $BSWAP - 500`
				else
					BSWAP=15868MB
					BSEXT2=15368MB
				fi
				parted -s /dev/block/mmcblk0 mkpartfs primary fat32 0 $BSEXT2
				parted -s /dev/block/mmcblk0 mkpartfs primary ext2 $BSEXT2 $BSWAP
				parted -s /dev/block/mmcblk0 mkpartfs primary linux-swap $BSWAP $DSIZE
				echo "SDcard splitted (fat32+ext2+swap)"
			;;
		esac
	;;
	*)
		print_usage
	;;
esac

do_exit 0
