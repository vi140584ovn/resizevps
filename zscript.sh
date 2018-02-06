#!/bin/bash
export LANG=en_US.utf8

function struck_win {
disk1=$disk"p1"
disk2=$disk"p2"
disk3=$disk"p3"
disk4=$disk"p4"

echo "# partition table of /dev/zvol/ZFSpool/$disk
unit: sectors
/dev/zvol/ZFSpool/$disk1 : start=     2048, size= $sizestruck, Id=7, bootable
/dev/zvol/ZFSpool/$disk2 : start=        0, size=        0, Id= 0
/dev/zvol/ZFSpool/$disk3 : start=        0, size=        0, Id= 0
/dev/zvol/ZFSpool/$disk4 : start=        0, size=        0, Id= 0
" > ./struck.txt
sfdisk /dev/zvol/ZFSpool/$disk < ./struck.txt --force
}

function struck_linux {
disk1=$disk"p1"
disk2=$disk"p2"
disk3=$disk"p3"
disk4=$disk"p4"

echo "# partition table of /dev/zvol/ZFSpool/$disk
unit: sectors
/dev/zvol/ZFSpool/$disk1 : start=     2048, size= $sizestruck, Id=83
/dev/zvol/ZFSpool/$disk2 : start=        0, size=        0, Id= 0
/dev/zvol/ZFSpool/$disk3 : start=        0, size=        0, Id= 0
/dev/zvol/ZFSpool/$disk4 : start=        0, size=        0, Id= 0
" > ./struck.txt
}

function write_virtualizor_base {
	pass=`grep dbpass /usr/local/virtualizor/universal.php | awk '{print $3}' | awk -F"'" '{print $2}'`;/usr/local/emps/bin/mysql -P 3178 -u root -p$pass -e "use virtualizor;update vps set space=$size where vps_name='$diskdown';update disks set size=$size where path like '%$disk';"
}

function ntfs_reduce {
	ntfsresize -f -s $size2fs"k" /dev/zvol/ZFSpool/$disk-part1
        struck_win
	zfs set volsize=$sizelv"K" ZFSpool/$disk
	write_virtualizor_base
	virsh create /etc/libvirt/qemu/$diskdown.xml	
}

function ntfs_increase {
	zfs set volsize=$sizelv"K" ZFSpool/$disk
	struck_win
	sleep 2
	ntfsresize -f /dev/zvol/ZFSpool/$disk-part1
	write_virtualizor_base
        virsh create /etc/libvirt/qemu/$diskdown.xml
}

function linux_reduce {
	e2fsck -fy /dev/zvol/ZFSpool/$disk-part1
	resize2fs -p /dev/zvol/ZFSpool/$disk-part1 $size2fs"K"
	sleep 1
	struck_linux
	sleep 1
	zfs set volsize=$sizelv"K" ZFSpool/$disk
	write_virtualizor_base
        virsh create /etc/libvirt/qemu/$diskdown.xml
}

function linux_increase {
	zfs set volsize=$sizelv"K" ZFSpool/$disk
	sleep 1
	struck_linux
	sleep 1
	e2fsck -fy /dev/zvol/ZFSpool/$disk-part1
	resize2fs /dev/zvol/ZFSpool/$disk-part1
	write_virtualizor_base
        virsh create /etc/libvirt/qemu/$diskdown.xml
}



###############################################################################
disk=$1
size=$2
if [[ "$disk" == "" || "$size" == "" ]];then
        echo "sh script.sh значение1 значения2"
        echo "значение1 -- название диска, например vs1033"
        echo "значение2 -- новый размер - значение задавать в G, например 15"
        echo "пример - /bin/bash zscript.sh vs1033 15"
        exit 0
fi
let "size2fs=$size*1024*1024"
let "sizelv=$size2fs+4096"
let "sizestruck=size2fs*2+2048"
diskdown=`echo "$disk" | awk -F 'vs' '{print $2}' | awk -F '-' '{print $1}'`
sizeaccess=`zfs list | grep $diskdown | awk '{print $4}' | awk -F'.' '{print $1}'`
pass=`grep dbpass /usr/local/virtualizor/universal.php | awk '{print $3}' | awk -F"'" '{print $2}'`;sizeorig=`/usr/local/emps/bin/mysql -P 3178 -u root -p$pass -e "use virtualizor; select space from vps where vps_name='$diskdown'" | grep -v space`
flag="0"
#echo $sizeaccess
#echo $size2fs
#echo $sizelv
#echo $sizestruck
#echo "orig $sizeorig"

if [[ "$size" -gt "$sizeaccess" && "$size" -gt 5 ]];then
	virsh shutdown $diskdown
	while [[ `virsh list --all | grep $diskdown | awk '{print $3}'` == "running" || `virsh list --all | grep $diskdown | awk '{print $3}'` == "paused" ]]
	do
        	sleep 1;
	        let "index = $index + 1"
        	if [ "$index" -gt "120" ];then
                	flag="1"
	                echo "$disk has not been stoped"
        	        exit 0
	        fi
	done
	echo "$disk has been stoped"

	if [ "$flag" == "0" ];then
		filesystem=`blkid -o value -s TYPE /dev/zvol/ZFSpool/$disk-part1`
		if [ "$filesystem" == "ntfs" ];then
			if [ "$sizeorig" -gt "$size" ];then
				ntfs_reduce
			fi
			if [ "$size" -gt "$sizeorig" ];then
				ntfs_increase
			fi
			if [ "$size" -eq "$sizeorig" ];then
                                echo "значення, яке було задане, відповідає розміру диска"
                        fi

		fi
		if [ "$filesystem" == "ext4" ];then
                       	if [ "$sizeorig" -gt "$size" ];then
                               	linux_reduce
                        fi
       	                if [ "$size" -gt "$sizeorig" ];then
               	                linux_increase
                       	fi
                        if [ "$size" -eq "$sizeorig" ];then
                                echo "значення, яке було задане, відповідає розміру диска"
                        fi
        	fi
		if [ "$filesystem" == "" ];then
			echo "можливо файлова система бита, щоб перевірте запустіть blkid /dev/zvol/ZFSpool/"$disk"-part1"
		fi
	fi
else echo "не достатньо вільного місця або місця < 6G"
fi

