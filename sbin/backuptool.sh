#!/sbin/sh
#
# Backup and restore proprietary Android system files
# CyanogenMod 4.2 (shade@chemlab.org)
#
# modified by rikupw for his recovery

CACHE=/system/sd/google

backup_file() {
    if [ -e "$1" ];
    then
        if [ "$2" != "" ];
        then
            echo "$2  $1" | md5sum -c -
            if [ $? -ne 0 ];
            then
                echo "MD5Sum check for $1 failed!";
                exit $?;
            fi
        fi
        cp $1 $CACHE/`basename $1`
    fi
}

restore_file() {
    FILE=`basename $1`
    DIR=`dirname $1`
    if [ -e "$CACHE/$FILE" ];
    then
        if [ ! -d "$DIR" ];
        then
            mkdir -p $DIR;
        fi
        cp -p $CACHE/$FILE $1;
        if [ "$2" != "" ];
        then
            rm $2;
        fi
    fi
}

case "$1" in
	backup)
		mount /system
		mount /system/sd
		backup_file /system/bin/akmd 0fe4224522291d52e888e339dc8b18d3
		backup_file /system/etc/01_qcomm_omx.cfg de9738a0facd97218cb1cecd7572ab04
		backup_file /system/etc/gps.conf 358b85156e192de70edca8345444ced6
		backup_file /system/etc/pvasflocal.cfg 3fead4f7a3fd2af3b66d655e7414950e
		backup_file /system/lib/libaudioeq.so fbfdc84045ab718694baf7e2f5fe1b49
		backup_file /system/lib/libcamera.so 22abec438532599c2a27979f88b4b45f
		backup_file /system/lib/libgps.so 31d32bac2d8e55105fb94b27b09e3a04
		backup_file /system/lib/libhgl.so b062a959ab3e1e3edb32a0a5e8a85557
		backup_file /system/lib/libhtc_acoustic.so 3342ad729ac37f1a348e328991c047a7
		backup_file /system/lib/libhtc_ril.so d072b2a29accad9bb6d0b2aa8ae65a8e
		backup_file /system/lib/libloc_api.so 51eb44a7ecd8e2eca4259ac67834d997
		backup_file /system/lib/libmm-adspsvc.so 2680660cb8a3cb1879bbfeb57a3ecbd0
		backup_file /system/lib/libOmxCore.so 8286ea6202a8ad93f405ed4d0d2157b1
		backup_file /system/lib/libOmxH264Dec.so 09c00dba61ff229f3cd79a0d3778a21d
		backup_file /system/lib/libOmxMpeg4Dec.so ebc27a7a5946fcb1811addf2a2dccee3
		backup_file /system/lib/libOmxVidEnc.so 338e374505d88687994a738da24c077b
		backup_file /system/lib/libomx_wmadec_sharedlibrary.so 37ba2cffe119ede93d63a0141f0a0861
		backup_file /system/lib/libomx_wmvdec_sharedlibrary.so 5f2e5bcc55c4da6b60306af3d4b6b594
		backup_file /system/lib/libopencorehw.so 1b1514b7203e9df065cd5ac9a2b5acc1
		backup_file /system/lib/libpvasfcommon.so 30ebc37bf6808e317d3440a98ad6da23
		backup_file /system/lib/libpvasflocalpbreg.so 6de66e1f38e1d5d34a6a46621cbeab0a
		backup_file /system/lib/libpvasflocalpb.so b483a2a1a8b06d58831cfedecb8cfc9a
		backup_file /system/lib/libqcamera.so 6ba4e8902840bc6fc40383dbe0d7e03d
		backup_file /system/lib/libqcomm_omx.so 4d351b85ae95af88acb5346bf7f5e651

		backup_file /system/app/BugReport.apk
		backup_file /system/app/EnhancedGoogleSearchProvider.apk
		backup_file /system/app/Gmail.apk
		backup_file /system/app/GmailProvider.apk
		backup_file /system/app/GoogleApps.apk
		backup_file /system/app/GoogleBackupTransport.apk
		backup_file /system/app/GoogleCheckin.apk
		backup_file /system/app/GoogleContactsProvider.apk
		backup_file /system/app/GooglePartnerSetup.apk
		backup_file /system/app/GoogleSettingsProvider.apk
		backup_file /system/app/GoogleSubscribedFeedsProvider.apk
		backup_file /system/app/gtalkservice.apk
		backup_file /system/app/LatinImeTutorial.apk
		backup_file /system/app/Maps.apk
		backup_file /system/app/MarketUpdater.apk
		backup_file /system/app/MediaUploader.apk
		backup_file /system/app/NetworkLocation.apk
		backup_file /system/app/SetupWizard.apk
		backup_file /system/app/Street.apk
		backup_file /system/app/Talk.apk
		backup_file /system/app/Vending.apk
		backup_file /system/app/VoiceSearch.apk
		backup_file /system/app/YouTube.apk
		backup_file /system/etc/permissions/com.google.android.gtalkservice.xml
		backup_file /system/etc/permissions/com.google.android.maps.xml
		backup_file /system/framework/com.google.android.gtalkservice.jar
		backup_file /system/framework/com.google.android.maps.jar
		backup_file /system/lib/libgtalk_jni.so
		;;
	restore)
		restore_file /system/bin/akmd
		restore_file /system/etc/01_qcomm_omx.cfg
		restore_file /system/etc/gps.conf
		restore_file /system/etc/pvasflocal.cfg
		restore_file /system/lib/libaudioeq.so
		restore_file /system/lib/libcamera.so
		restore_file /system/lib/libgps.so
		restore_file /system/lib/libhgl.so
		restore_file /system/lib/libhtc_acoustic.so
		restore_file /system/lib/libhtc_ril.so
		restore_file /system/lib/libloc_api.so
		restore_file /system/lib/libmm-adspsvc.so
		restore_file /system/lib/libOmxCore.so
		restore_file /system/lib/libOmxH264Dec.so
		restore_file /system/lib/libOmxMpeg4Dec.so
		restore_file /system/lib/libOmxVidEnc.so
		restore_file /system/lib/libomx_wmadec_sharedlibrary.so
		restore_file /system/lib/libomx_wmvdec_sharedlibrary.so
		restore_file /system/lib/libopencorehw.so
		restore_file /system/lib/libpvasfcommon.so
		restore_file /system/lib/libpvasflocalpbreg.so
		restore_file /system/lib/libpvasflocalpb.so
		restore_file /system/lib/libqcamera.so
		restore_file /system/lib/libqcomm_omx.so

		restore_file /system/app/BugReport.apk
		restore_file /system/app/EnhancedGoogleSearchProvider.apk /system/app/GoogleSearch.apk
		restore_file /system/app/Gmail.apk
		restore_file /system/app/GmailProvider.apk
		restore_file /system/app/GoogleApps.apk
		restore_file /system/app/GoogleBackupTransport.apk
		restore_file /system/app/GoogleCheckin.apk
		restore_file /system/app/GoogleContactsProvider.apk /system/app/ContactsProvider.apk
		restore_file /system/app/GooglePartnerSetup.apk
		restore_file /system/app/GoogleSettingsProvider.apk
		restore_file /system/app/GoogleSubscribedFeedsProvider.apk /system/app/SubscribedFeedsProvider.apk
		restore_file /system/app/gtalkservice.apk
		restore_file /system/app/LatinImeTutorial.apk
		restore_file /system/app/Maps.apk
		restore_file /system/app/MarketUpdater.apk
		restore_file /system/app/MediaUploader.apk
		restore_file /system/app/NetworkLocation.apk
		restore_file /system/app/SetupWizard.apk /system/app/Provision.apk
		restore_file /system/app/Street.apk
		restore_file /system/app/Talk.apk
		restore_file /system/app/Vending.apk
		restore_file /system/app/VoiceSearch.apk
		restore_file /system/app/YouTube.apk
		restore_file /system/etc/permissions/com.google.android.gtalkservice.xml
		restore_file /system/etc/permissions/com.google.android.maps.xml
		restore_file /system/framework/com.google.android.gtalkservice.jar
		restore_file /system/framework/com.google.android.maps.jar
		restore_file /system/lib/libgtalk_jni.so
        ;;
	*) 
		echo "Usage: $0 {backup|restore}"
		exit 1
esac

exit 0
