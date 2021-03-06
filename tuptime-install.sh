#!/bin/sh

#
# Tuptime installation linux script
# v.1.8.3
#
# Usage:
#	bash tuptime-install.sh		Normal installation
#	bash tuptime-install.sh -d 	Installation using dev branch
#

# Destination dir for executable file
D_BIN='/usr/bin'

# PID 1 process
PID1=`grep 'Name' /proc/1/status | cut -f2`

# Swich dev branch
DEV=0


# Check root execution
if [ "$(id -u)" != "0" ]; then
  echo "Please run this script as root"
  exit
fi

# Test arguments
while test $# -gt 0; do
    case "$1" in
        -d) DEV=1
           ;;
    esac
    shift
done

# Test if it is a linux system
if [ "$(expr substr $(uname -s) 1 5)" != "Linux" ]; then
	echo "Sorry, only for Linux systems"
	exit 1
fi

# Test if git is installed
git --version > /dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "ERROR: \"git\" command not available"
	echo "Please, install it"; exit 1
fi

# Test if python is installed
pyver=`python3 --version 2> /dev/null`
if [ $? -ne 0 ]; then
        echo "ERROR: Python not available"
        echo "Please, install version 3 or greater"; exit 1
else
	# Test if version 3 or avobe of python is installed
        pynum=`echo ${pyver} | tr -d '.''' | grep -Eo  '[0-9]*' | head -1 | cut -c 1-2`
        if [ $pynum -lt 30 ] ; then
                echo "ERROR: Its needed Python version 3, not ${pyver}"
                echo "Please, upgrade it."; exit 1
        else
		# Test if all modules needed are available
		pymod=`python3 -c "import sys, os, argparse, locale, platform, signal, logging, sqlite3, datetime"`
                if [ $? -ne 0 ]; then
                        echo "ERROR: Please, ensure that these Python modules are available in the local system:"
                        echo "sys, os, optparse, sqlite3, locale, platform, datetime, logging"; exit 1
                fi
        fi
fi

# Set SystemD path
if [ -d /usr/lib/systemd/system/ ]; then
	SYSDPATH='/usr/lib/systemd/system/'
else
	SYSDPATH='/lib/systemd/system/'
fi

# Set Selinux swich
SELX=`getenforce 2> /dev/null`
if [ "${SELX}" = 'Enforcing' ]; then
        echo "Selinux enabled in Enforcing"
	SELX='true'
else
	SELX='false'
fi

# Temporary dir for clone repo into it
F_TMP1=`mktemp -d`

echo ""
echo "++ Tuptime installation script ++"
echo ""

echo "+ Cloning repository"
if [ ${DEV} -eq 1 ]; then
        echo "  ...using dev branch"
	git clone -b dev https://github.com/rfrail3/tuptime.git ${F_TMP1} || exit
else
	git clone https://github.com/rfrail3/tuptime.git ${F_TMP1} || exit
fi
echo '  [OK]'

echo "+ Copying files"
install -m 755 ${F_TMP1}/src/tuptime ${D_BIN}/tuptime || exit
if [ ${SELX} = true ]; then restorecon -vF ${D_BIN}/tuptime; fi
echo '  [OK]'

echo "+ Creating Tuptime user"
useradd -h > /dev/null 2>&1
if [ $? -eq 0 ]; then
	useradd --system --no-create-home --home-dir '/var/lib/tuptime' \
        	--shell '/bin/false' --comment 'Tuptime execution user' tuptime || exit
else
	adduser -S -H -h '/var/lib/tuptime' -s '/bin/false' tuptime || exit
fi
echo '  [OK]'

echo "+ Creating Tuptime db"
tuptime -x
echo '  [OK]'

echo "+ Setting Tuptime db ownership"
chown -R tuptime /var/lib/tuptime || exit
chmod 755 /var/lib/tuptime || exit
echo '  [OK]'

echo "+ Executing Tuptime with tuptime user for testing"
su -s /bin/sh tuptime -c "tuptime -x" || exit
echo '  [OK]'

# Install init
if [ ${PID1} = 'systemd' ]; then
	echo "+ Copying Systemd file"
	cp -a ${F_TMP1}/src/systemd/tuptime.service ${SYSDPATH} || exit
	if [ ${SELX} = true ]; then restorecon -vF ${SYSDPATH}tuptime.service; fi
	systemctl daemon-reload || exit
	systemctl enable tuptime.service && systemctl start tuptime.service || exit
	echo '  [OK]'
elif [ ${PID1} = 'init' ] && [ -f /etc/rc.d/init.d/functions ]; then
	echo "+ Copying  SysV init RedHat file"
	install -m 755 ${F_TMP1}/src/init.d/redhat/tuptime /etc/init.d/tuptime || exit
	if [ ${SELX} = true ]; then restorecon -vF /etc/init.d/tuptime; fi
	chkconfig --add tuptime || exit
	chkconfig tuptime on || exit
	echo '  [OK]'
elif [ ${PID1} = 'init' ] && [ -f /lib/lsb/init-functions ]; then
	echo "+ Copying SysV init Debian file"
	install -m 755 ${F_TMP1}/src/init.d/debian/tuptime /etc/init.d/tuptime || exit
	if [ ${SELX} = true ]; then restorecon -vF /etc/init.d/tuptime; fi
	update-rc.d tuptime defaults || exit
	echo '  [OK]'
elif [ ${PID1} = 'init' ] && [ -f /etc/rc.conf ]; then
	echo "+ Copying OpenRC file for init"
	install -m 755 ${F_TMP1}/src/openrc/tuptime /etc/init.d/ || exit
	if [ ${SELX} = true ]; then restorecon -vF /etc/init.d/tuptime; fi
	rc-update add tuptime default && rc-service tuptime start || exit
	echo '  [OK]'
elif [ ${PID1} = 'openrc-init' ]; then
	echo "+ Copying OpenRC file for openrc-init"
	install -m 755 ${F_TMP1}/src/openrc/tuptime /etc/init.d/ || exit
	if [ ${SELX} = true ]; then restorecon -vF /etc/init.d/tuptime; fi
	rc-update add tuptime default && rc-service tuptime start || exit
	echo '  [OK]'
else
	echo "#########################################"
	echo " WARNING - Any init file for your system"
	echo "#########################################"
	echo '  [BAD]'
fi

# Install cron
if [ -d /etc/cron.d/ ]; then
	echo "+ Copying Cron file"
	cp -a ${F_TMP1}/src/cron.d/tuptime /etc/cron.d/tuptime || exit
	if [ ${SELX} = true ]; then restorecon -vF /etc/cron.d/tuptime; fi
	echo '  [OK]'
elif [ -d ${SYSDPATH} ]; then
	echo "+ Copying tuptime-cron.timer and .service"
	cp -a ${F_TMP1}/src/systemd/tuptime-cron.*  ${SYSDPATH} || exit
	if [ ${SELX} = true ]; then restorecon -vF ${SYSDPATH}tuptime-cron.*; fi
	systemctl enable tuptime-cron.timer && systemctl start tuptime-cron.timer
	echo '  [OK]'
else
	echo "#########################################"
	echo " WARNING - Any cron file for your system"
	echo "#########################################"
	echo '  [BAD]'
fi

echo "+ Enjoy!"
echo ""

tuptime
