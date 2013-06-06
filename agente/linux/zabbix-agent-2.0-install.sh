#!/bin/bash
#
#title           :zabbix-agent-2.0-install.sh
#description     :This script will install Zabbix Agent
#date            :20130520
#version         :0.1    
#usage           :bash zabbix-agent-2.0-install.sh
#notes           :Attention, read the INSTALL before continuing
### END SCRIPT INFO
#
# 
# Author: Valter Douglas Lisboa Jr. <valter.junior@4linux.com.br>
#         Modified by Tassya Ventura Frigieri <tassya.frigieri@4linux.com.br>
#          	      Alexandre Laniado <alexandre.it@4linux.com.br>
#

SISTEMA=$(dialog --stdout --title 'Perfil' --menu 'Escolha o perfil da instalação:' 0 0 0 \
   Debian/Ubuntu       'Instalação .deb' \
   RedHat/CentOS       'Instalação .rpm' )           

VERSION=$(dialog --stdout --title 'Versão' --inputbox 'Favor inserir a versão do zabbix' 0 40)
SERVERIP=$(dialog --stdout --title 'IP do Servidor' --inputbox 'Favor inserir o IP do servidor zabbix' 0 50)
HOSTIP=$(dialog --stdout --title 'IP do Host' --inputbox 'Favor inserir o IP desse Host' 0 50)
TARGZ="zabbix-$VERSION.tar.gz"
PKGDIR=$PWD
SRCDIR=$PWD/zabbix-$VERSION
INSTALLDIR=/opt/zabbix-$VERSION
ZABBIXCONFDIR=$INSTALLDIR/etc
CONFIGPKG=$PKGDIR/zabbix-agent-2.0-config.tar
BOOTDEBIAN=$PKGDIR/zabbix-agent-bootscript-debian.tar
BOOTCENTOS=$PKGDIR/zabbix-agent-bootscript-centos.tar
INSTALLLOG=/tmp/zabbix-agent-2.0-install.log
CPUNUM=`cat /proc/cpuinfo |grep ^processor|wc -l`

touch $INSTALLLOG
( dialog --title 'Instalando....' --tailbox $INSTALLLOG 80 120 ) &

if [ $SISTEMA == "Debian/Ubuntu" ]; then
echo "Installing Zabbix agent version $VERSION..."  >> $INSTALLLOG

echo -n "* Checking for source... " >> $INSTALLLOG
if [ -r $TARGZ ]; then
	echo "OK" >> $INSTALLLOG
else
	echo "source not found. FAIL." >> $INSTALLLOG
	exit 1
fi

echo -n "* Checking for bootscript package... " >> $INSTALLLOG
if [[ -r $BOOTDEBIAN ]]; then
	echo "OK" >> $INSTALLLOG
else
	echo "Cannot find the boot package $BOOTDEBIAN" >> $INSTALLLOG
	exit 1
fi

echo -n "* Checking for config package... " >> $INSTALLLOG
if [[ -r $CONFIGPKG ]]; then
	echo "OK" >> $INSTALLLOG
else
	echo "Cannot find the config package $CONFIGPKG" >> $INSTALLLOG
	exit 1
fi

echo -n "* User/Group... " >> $INSTALLLOG
grep '^zabbix:' /etc/group &> /dev/null
if [[ $? -ne 0 ]]; then
	groupadd zabbix || exit 1
fi
grep '^zabbix:' /etc/passwd &> /dev/null
if [[ $? -ne 0 ]]; then
	useradd -m -s /bin/bash -g zabbix zabbix || exit 1
fi
echo "OK" >> $INSTALLLOG

echo -n "* Expanding source... " >> $INSTALLLOG
if [[ -d $SRCDIR ]]; then
	rm -rf $SRCDIR
fi
tar xf $PKGDIR/$TARGZ -C $PKGDIR || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Installing dependences... " >> $INSTALLLOG
aptitude -y install build-essential make pkg-config libldap2-dev &>> $INSTALLLOG || exit 1
echo OK >> $INSTALLLOG

echo -n "* Compiling... " >> $INSTALLLOG
if [[ -d $INSTALLDIR ]]; then
	rm -rf $INSTALLDIR || exit 1
fi
cd $PKGDIR/zabbix-$VERSION
./configure --prefix=$INSTALLDIR --mandir=/usr/share/man --disable-server --disable-static --disable-proxy --enable-agent --with-libcurl --with-ssh2 --with-ldap &>> $INSTALLLOG &&
make -j $CPUNUM &>> $INSTALLLOG &&
make install &>> $INSTALLLOG || exit 1
rm -rf $INSTALLDIR/sbin/zabbix_agent
rm -rf $INSTALLDIR/etc/*
echo "OK" >> $INSTALLLOG

echo -n "* Setting the link... " >> $INSTALLLOG
cd /opt
if [ -h zabbix ]; then
	rm -f zabbix
fi
ln -sf /opt/zabbix-$VERSION /opt/zabbix || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Stripping binaries... " >> $INSTALLLOG
strip --strip-all $INSTALLDIR/{bin,sbin}/* || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Setting the PATH... " >> $INSTALLLOG
cat > /etc/profile.d/zabbix-path.sh << "EOF"
export PATH="$PATH:/opt/zabbix/sbin:/opt/zabbix/bin"
EOF

echo "OK" >> $INSTALLLOG

echo -n "* Creating directories... " >> $INSTALLLOG
mkdir -p /var/{run,log}/zabbix || exit 1
chown zabbix. /var/{run,log}/zabbix || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Installing configs... " >> $INSTALLLOG
tar xf $CONFIGPKG -C /opt/zabbix || exit 1
chown root.zabbix $ZABBIXCONFDIR -R || exit 1
find $ZABBIXCONFDIR -type d -exec chmod 0750 {} \;
find $ZABBIXCONFDIR -type f -exec chmod 0640 {} \;
echo "OK" >> $INSTALLLOG

echo -n "* Applying configurations... " >> $INSTALLLOG
sed -i -e "s@\(^Server\).*@\1=127.0.0.1,$SERVERIP,$HOSTIP@g" $ZABBIXCONFDIR/agentd.d/passivechecks.conf || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Installing bootscripts... " >> $INSTALLLOG
tar xf $BOOTDEBIAN -C / || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Initializing... " >> $INSTALLLOG
service zabbix-agentd start &> /dev/null || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Setting on boot... " >> $INSTALLLOG
if [ -x /usr/sbin/update-rc.d ]; then
	/usr/sbin/update-rc.d zabbix-agentd defaults &> /dev/null || exit 1
else
	insserv zabbix-agentd &> /dev/null || exit 1
fi
echo "OK" >> $INSTALLLOG

echo >> $INSTALLLOG
echo "Installation complete. Don't forget the . /etc/profile to load the new PATH in this session" >> $INSTALLLOG
echo >> $INSTALLLOG
exit 0

else

echo "Installing Zabbix agent version $VERSION..." >> $INSTALLLOG

echo -n "* Checking for source... " >> $INSTALLLOG
if [ -r $TARGZ ]; then
	echo "OK" >> $INSTALLLOG
else
	echo "source not found. FAIL." >> $INSTALLLOG
	exit 1
fi

echo -n "* Checking for bootscript package... " >> $INSTALLLOG
if [[ -r $BOOTCENTOS ]]; then
	echo "OK" >> $INSTALLLOG
else
	echo "Cannot find the boot package $BOOTCENTOS" >> $INSTALLLOG
	exit 1
fi

echo -n "* Checking for config package... " >> $INSTALLLOG
if [[ -r $CONFIGPKG ]]; then
	echo "OK" >> $INSTALLLOG
else
	echo "Cannot find the config package $CONFIGPKG" >> $INSTALLLOG
	exit 1
fi

echo -n "* User/Group... "
grep '^zabbix:' /etc/group &> /dev/null
if [[ $? -ne 0 ]]; then
	groupadd zabbix || exit 1
fi
grep '^zabbix:' /etc/passwd &> /dev/null
if [[ $? -ne 0 ]]; then
	useradd -m -s /bin/bash -g zabbix zabbix || exit 1
fi
echo "OK" >> $INSTALLLOG
 
echo -n "* Expanding source... " >> $INSTALLLOG
if [[ -d $SRCDIR ]]; then
	rm -rf $SRCDIR || exit 1
fi
tar xf $TARGZ -C /usr/src || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Installing dependences... " >> $INSTALLLOG
yum -y install gcc make.x86_64 openldap-devel.x86_64 &> $INSTALLLOG || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Compiling... " >> $INSTALLLOG
if [[ -d $INSTALLDIR ]]; then
	rm -rf $INSTALLDIR || exit 1
fi
cd PKGDIR/zabbix-$VERSION
./configure --prefix=$INSTALLDIR --mandir=/usr/share/man --disable-server --disable-static --disable-proxy --enable-agent --with-libcurl --with-ssh2 --with-ldap &>> $INSTALLLOG &&
make -j $CPUNUM &>> $INSTALLLOG &&
make install &>> $INSTALLLOG || exit 1
rm -rf $INSTALLDIR/sbin/zabbix_agent
rm -rf $INSTALLDIR/etc/*
echo "OK" >> $INSTALLLOG

echo -n "* Setting the link... " >> $INSTALLLOG
cd /opt
if [ -h zabbix ]; then
	rm -f zabbix
fi
ln -sf /opt/zabbix-$VERSION /opt/zabbix || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Stripping binaries... " >> $INSTALLLOG
strip --strip-all $INSTALLDIR/{bin,sbin}/* || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Setting the PATH... " >> $INSTALLLOG
cat > /etc/profile.d/zabbix-path.sh << "EOF"
export PATH="$PATH:/opt/zabbix/sbin:/opt/zabbix/bin"
EOF

echo "OK" >> $INSTALLLOG

echo -n "* Creating directories... " >> $INSTALLLOG
mkdir -p /var/{run,log}/zabbix || exit 1
chown zabbix.zabbix /var/{run,log}/zabbix || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Installing configs... " >> $INSTALLLOG
tar xf $CONFIGPKG -C /opt/zabbix || exit 1
chown root.zabbix $ZABBIXCONFDIR -R || exit 1
find $ZABBIXCONFDIR -type d -exec chmod 0750 {} \;
find $ZABBIXCONFDIR -type f -exec chmod 0640 {} \;
echo "OK" >> $INSTALLLOG

echo -n "* Applying configurations... " >> $INSTALLLOG
sed -i -e "s@\(^Server\).*@\1=127.0.0.1,$SERVERIP,$HOSTIP@g" $ZABBIXCONFDIR/agentd.d/passivechecks.conf || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Installing bootscripts... " >> $INSTALLLOG
tar xf $BOOTCENTOS -C / || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Setting on boot... " >> $INSTALLLOG
chkconfig --add zabbix-agent &> /dev/null || exit 1
echo "OK" >> $INSTALLLOG

echo -n "* Initializing... " >> $INSTALLLOG
service zabbix-agent restart &> /dev/null || exit 1
echo "OK" >> $INSTALLLOG

echo >> $INSTALLLOG
echo "Installation complete. Don't forget the . /etc/profile to load the new PATH in this session" >> $INSTALLLOG
echo >> $INSTALLLOG

exit 0

fi
