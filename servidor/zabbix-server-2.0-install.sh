#!/bin/bash
#
#project	 :4Linux Free Software Solutions
#title           :zabbix-2.0-install.sh
#description     :This script will install Zabbix Server
#date            :20130520
#version         :1.0    
#usage           :bash zabbix-2.0-install.sh
#notes           :Attention, read the INSTALL before continuing
### END SCRIPT INFO
#
# Authores:     Alexandre Laniado <alexandre.lt@4linux.com.br>
#           	Tassya Ventura Frigieri   <tassya.frigieri@4linux.com.br>

SISTEMA=$(dialog --stdout --title 'Perfil' --menu 'Escolha o perfil da instalação:' 0 0 0 \
   Debian/Ubuntu       'Instalação .deb' \
   RedHat/CentOS       'Instalação .rpm' )           
if [ $SISTEMA == "Debian/Ubuntu" ]; then
	MYVERSION=$(dialog --stdout --title 'Release' --inputbox 'Favor inserir o NOME da versão do sistema. EX: squeeze' 0 40)
fi

VERSION=$(dialog --stdout --title 'Versão' --inputbox 'Favor inserir a versão do zabbix' 0 40)
SERVERIP=$(dialog --stdout --title 'IP do Servidor' --inputbox 'Favor inserir o IP do servidor zabbix' 0 50)

TIPOBANCO=$(dialog --stdout --title 'Base de Dados' --menu 'Qual o banco de dados que será utilizado:' 0 45 0 \
   PostgreSQL    'Base de dados')

BANCO=$(dialog --stdout --title 'Banco de Dados' --menu 'O Banco de dados será local ou remoto:' 0 45 0 \
   Localhost    'Base de dados' \
   Remoto       'Base de dados' )
if [ $BANCO == "Localhost" ]; then
        DBHOST="localhost"
else
        DBHOST=$(dialog --stdout --title 'Banco de Dados' --inputbox 'Favor inserir o IP do servidor do Banco de Dados' 0 50)
fi

DBNAME=$(dialog --stdout --title 'Banco de Dados' --inputbox 'Favor inserir o nome da Base de Dados' 0 40)
DBUSER=$(dialog --stdout --title 'Banco de Dados' --inputbox 'Favor inserir o nome do usuario da Base de Dados' 0 50) 
DBPASSWORD=$(dialog --stdout --title 'Banco de Dados' --inputbox 'Favor inserir a senha do usuario da Base de Dados' 0 50)

TARGZ="zabbix-$VERSION.tar.gz"
INSTALLDIR=/opt/zabbix-$VERSION
ZABBIXCONFDIR=$INSTALLDIR/etc
PKGDIR=$PWD
SRCDIR=$PWD/zabbix-$VERSION
CONFIGPKG=$PKGDIR/zabbix-server-2.0-config.tar
BOOTDEBIAN=$PKGDIR/zabbix-server-bootscript-debian.tar
BOOTCENTOS=$PKGDIR/zabbix-server-bootscript-centos.tar
INSTALLLOG=/tmp/zabbix-server-2.0-install.log
CPUNUM=`cat /proc/cpuinfo |grep ^processor|wc -l`

touch $INSTALLLOG
( dialog --title 'Instalando....' --tailbox $INSTALLLOG 80 120 ) &

if [ $SISTEMA == "Debian/Ubuntu" ]; then
	echo "Installing zabbix server version $VERSION..." >> $INSTALLLOG
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
			rm -rf $SRCDIR || exit 1
		fi
	tar xf $TARGZ -C $PKGDIR || exit 1
	echo "OK" >> $INSTALLLOG

	if [ $BANCO == "Localhost" ]; then
		echo -n "* Verificando pgdg... " >> $INSTALLLOG
		grep "deb http://apt.postgresql.org/pub/repos/apt/ $MYVERSION-pgdg main" /etc/apt/sources.list &> /dev/null
			if [[ $? -ne 0  ]]; then
				wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - || &>> $INSTALLLOG || exit 1
				echo "deb http://apt.postgresql.org/pub/repos/apt/ $MYVERSION-pgdg main" >> /etc/apt/sources.list ; aptitude update &> /dev/null || exit 1
	
			fi
		echo "OK" >> $INSTALLLOG

		echo -n "* Instalando Banco PostgreSQL ... " >> $INSTALLLOG
		aptitude -y install postgresql-9.2 &>> $INSTALLLOG

		su postgres -c "psql -c \"CREATE DATABASE $DBNAME\"" &> /dev/null
		su postgres -c "psql -c \"CREATE ROLE $DBUSER LOGIN PASSWORD '$DBPASSWORD'\"" &>> $INSTALLLOG

		echo "host    $DBNAME    $DBUSER      127.0.0.1/32            md5
		host    $DBNAME    $DBUSER      ::1/128            	     md5" >> /etc/postgresql/9.2/main/pg_hba.conf  

		cat $PKGDIR/zabbix-$VERSION/database/postgresql/schema.sql | su - postgres -c "psql $DBNAME" &>> $INSTALLLOG
		cat $PKGDIR/zabbix-$VERSION/database/postgresql/images.sql | su - postgres -c "psql $DBNAME" &>> $INSTALLLOG
		cat $PKGDIR/zabbix-$VERSION/database/postgresql/data.sql | su - postgres -c "psql $DBNAME" &>> $INSTALLLOG

		su postgres -c "psql -d $DBNAME -c \"GRANT SELECT,UPDATE,DELETE,INSERT ON ALL TABLES IN SCHEMA public TO $DBUSER\"" &>> $INSTALLLOG
		service postgresql restart &>> $INSTALLLOG
		echo "OK" >> $INSTALLLOG

	fi

	echo -n "* Installing dependences... " >> $INSTALLLOG
	aptitude -y install postgresql-server-dev-9.2 build-essential make pkg-config libssh2-1-dev libopenipmi-dev libsnmp-dev libiksemel-dev libcurl4-gnutls-dev apache2 libapache2-mod-php5 php5-gd php5-pgsql php5-ldap &>> $INSTALLLOG || exit 1
	echo "OK" >> $INSTALLLOG

	echo -n "* Compiling... " >> $INSTALLLOG
		if [[ -d $INSTALLDIR ]]; then
			rm -rf $INSTALLDIR || exit 1
		fi
	cd $PKGDIR/zabbix-$VERSION
	./configure --prefix=/opt/zabbix-$VERSION --mandir=/usr/share/man --enable-server --disable-static --disable-proxy --enable-agent --enable-ipv6 --with-postgresql --with-jabber --with-libcurl --with-net-snmp --with-ssh2 --with-openipmi --with-ldap &>> $INSTALLLOG &&
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
	ln -sf zabbix-$VERSION zabbix || exit 1
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
	tar xf $CONFIGPKG -C /opt/zabbix/ || exit 1
	chown root.zabbix $ZABBIXCONFDIR -R || exit 1
	find $ZABBIXCONFDIR -type d -exec chmod 0750 {} \;
	find $ZABBIXCONFDIR -type f -exec chmod 0640 {} \;
	echo "OK" >> $INSTALLLOG

	echo -n "* Applying configurations... " >> $INSTALLLOG
	sed -i -e "s@\(^Server\).*@\1=127.0.0.1,$SERVERIP@g" $ZABBIXCONFDIR/agentd.d/passivechecks.conf || exit 1
	sed -i -e "s@\(^DBHost\).*@\1=$DBHOST@g" $ZABBIXCONFDIR/server.d/database.conf || exit 1
	sed -i -e "s@\(^DBName\).*@\1=$DBNAME@g" $ZABBIXCONFDIR/server.d/database.conf || exit 1
	sed -i -e "s@\(^DBUser\).*@\1=$DBUSER@g" $ZABBIXCONFDIR/server.d/database.conf || exit 1
	sed -i -e "s@\(^DBPassword\).*@\1=$DBPASSWORD@g" $ZABBIXCONFDIR/server.d/database.conf || exit 1
	echo "OK" >> $INSTALLLOG

	echo -n "* Installing bootscripts... " >> $INSTALLLOG
	tar xf $BOOTDEBIAN -C / || exit 1
	echo "OK" >> $INSTALLLOG

	echo -n "* Initializing... " >> $INSTALLLOG
	service zabbix-agentd start &> /dev/null || exit 1
	service zabbix-server start &> /dev/null || exit 1
	echo "OK" >> $INSTALLLOG

	echo -n "* Setting on boot... " >> $INSTALLLOG
		if [ -x /usr/sbin/update-rc.d ]; then
			/usr/sbin/update-rc.d zabbix-agentd defaults &> /dev/null || exit 1
        		/usr/sbin/update-rc.d zabbix-server defaults &> /dev/null || exit 1
		else
			insserv zabbix-agentd &> /dev/null || exit 1
			insserv zabbix-server &> /dev/null || exit 1
		fi
	echo "OK" >> $INSTALLLOG

	echo -n "* Setting on Frontend... " >> $INSTALLLOG
	mkdir -p /var/lib/zabbix/$VERSION
	ln -s /var/lib/zabbix/$VERSION /var/lib/zabbix/frontend
	cp -a $PKGDIR/zabbix-$VERSION/frontends/php/* /var/lib/zabbix/frontend/
	find /var/lib/zabbix/frontend/ -type d -exec chmod 0750 {} \;
	find /var/lib/zabbix/frontend/ -type f -exec chmod 0640 {} \;
	chown -R root.www-data /var/lib/zabbix/frontend/
	chmod 0770 /var/lib/zabbix/frontend/conf
cat << EOF > /etc/apache2/sites-available/zabbix-frontend
<VirtualHost *:80>
	ServerAdmin webmaster@localhost.com.br

	DocumentRoot /var/lib/zabbix/frontend
	<Directory />
		Options FollowSymLinks
		AllowOverride None
	</Directory>
	<Directory /var/lib/zabbix/frontend>
		Options Indexes FollowSymLinks MultiViews
		AllowOverride None
		Order allow,deny
		allow from all
	</Directory>
ErrorLog \${APACHE_LOG_DIR}/error-zabbix-frontend.log
LogLevel warn
	CustomLog \${APACHE_LOG_DIR}/access-zabbix-frontend.log combined
</VirtualHost>
EOF

		if [ -L /etc/apache2/sites-enabled/000-default ]; then
			rm /etc/apache2/sites-enabled/000-default
		elif [ -e /etc/apache2/sites-enabled/000-default ]; then
			echo "O arquivo /etc/apache2/sites-enabled/000-default nao eh um link simbolico!" >> $INSTALLLOG
			echo "Movendo o conteudo original para /var/backups" >> $INSTALLLOG
			mv /etc/apache2/sites-enabled/000-default /var/backups
		fi
	ln -sf /etc/apache2/sites-available/zabbix-frontend /etc/apache2/sites-enabled/zabbix-frontend
	sed -i -e 's/^max_execution_time = 30/max_execution_time = 300/g' /etc/php5/apache2/php.ini
	sed -i -e 's/^post_max_size = 8M/post_max_size = 16M/g' /etc/php5/apache2/php.ini
	sed -i -e 's/^max_input_time = 60/max_input_time = 300/g' /etc/php5/apache2/php.ini
	sed -i -e 's/^;date.timezone =/date.timezone = America\/Sao_Paulo/g' /etc/php5/apache2/php.ini
	/etc/init.d/apache2 restart || exit 1

	echo >> $INSTALLLOG
	echo "Installation complete. Don't forget the . /etc/profile to load the new PATH in this session" >> $INSTALLLOG
	echo >> $INSTALLLOG

	killall dialog
	dialog  --title "Instalacao Completa" --msgbox "Pressione ENTER para terminar." 0 0
	exit 0
else
	echo "Installing Zabbix Server version $VERSION..." >> $INSTALLLOG
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
			rm -rf $SRCDIR || exit 1
		fi
	tar xf $TARGZ -C $PKGDIR || exit 1
	echo "OK" >> $INSTALLLOG

	 if [ $BANCO == "Localhost" ]; then
		echo -n "* Verificando backports postgresql... " >> $INSTALLLOG
		yum -y localinstall http://yum.postgresql.org/9.2/redhat/rhel-6-x86_64/pgdg-centos92-9.2-6.noarch.rpm &>> $INSTALLLOG || exit 1
		echo "OK" >> $INSTALLLOG

		echo -n "* Instalando Banco PostgreSQL 9.2... " >> $INSTALLLOG
		yum -y  install postgresql92-server.x86_64  &>> $INSTALLLOG || exit 1
		/etc/init.d/postgresql-9.2 initdb

		su postgres -c "psql -c \"CREATE DATABASE $DBNAME\"" &>> $INSTALLLOG
		su postgres -c "psql -c \"CREATE ROLE $DBUSER LOGIN PASSWORD '$DBPASSWORD'\"" &>> $INSTALLLOG

		echo "host    $DBNAME    $DBUSER      127.0.0.1/32            md5
		host    $DBNAME    $DBUSER      ::1/128            	     md5" >> /var/lib/pgsql/9.2/data/pg_hba.conf  

		cat $PKGDIR/zabbix-$VERSION/database/postgresql/schema.sql | su - postgres -c "psql $DBNAME" &>> $INSTALLLOG
		cat $PKGDIR/zabbix-$VERSION/database/postgresql/images.sql | su - postgres -c "psql $DBNAME" &>> $INSTALLLOG
		cat $PKGDIR/zabbix-$VERSION/database/postgresql/data.sql | su - postgres -c "psql $DBNAME" &>> $INSTALLLOG

		su postgres -c "psql -d $DBNAME -c \"GRANT SELECT,UPDATE,DELETE,INSERT ON ALL TABLES IN SCHEMA public TO $DBUSER\"" &>> $INSTALLLOG
		chkconfig postgresql-9.2 on
		service postgresql-9.2 restart &>> $INSTALLLOG
		echo "OK" >> $INSTALLLOG

	fi

	echo -n "* Installing dependences... " >> $INSTALLLOG
	yum -y localinstall http://dl.atrpms.net/el6-x86_64/atrpms/stable/atrpms-repo-6-6.el6.x86_64.rpm &>> $INSTALLLOG || exit 1
	yum -y install gcc make postgresql-devel.x86_64 iksemel-devel.x86_64 libcurl-devel.x86_64 net-snmp-devel.x86_64 libssh2-devel.x86_64 OpenIPMI-devel.x86_64 openldap-devel.x86_64 httpd.x86_64 php-gd.x86_64 php-pgsql.x86_64 php-ldap.x86_64 php php.x86_64 php-bcmath php-mbstring php-xmlwriter php-xmlreader &>> $INSTALLLOG || exit 1
	echo "OK" >> $INSTALLLOG

	echo -n "* Compiling... " >> $INSTALLLOG
		if [[ -d $INSTALLDIR ]]; then
			rm -rf $INSTALLDIR || exit 1
		fi
	cd $PKGDIR/zabbix-$VERSION
	./configure --prefix=/opt/zabbix-$VERSION --mandir=/usr/share/man --enable-server --disable-static --disable-proxy --enable-agent --enable-ipv6 --with-postgresql --with-jabber --with-libcurl --with-net-snmp --with-ssh2 --with-openipmi --with-ldap &>> $INSTALLLOG &&
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
	ln -sf zabbix-$VERSION zabbix || exit 1
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
	chown zabbix. /var/*/zabbix || exit 1
	echo "OK" >> $INSTALLLOG

	echo -n "* Installing configs... " >> $INSTALLLOG
	tar xf $CONFIGPKG -C /opt/zabbix/ || exit 1
	chown root.zabbix $ZABBIXCONFDIR -R || exit 1
	find $ZABBIXCONFDIR -type d -exec chmod 0750 {} \;
	find $ZABBIXCONFDIR -type f -exec chmod 0640 {} \;
	echo "OK" >> $INSTALLLOG

	echo -n "* Applying configurations... " >> $INSTALLLOG
	sed -i -e "s@\(^Server\).*@\1=127.0.0.1,$SERVERIP@g" $ZABBIXCONFDIR/agentd.d/passivechecks.conf || exit 1
	sed -i -e "s@\(^DBHost\).*@\1=$DBHOST@g" $ZABBIXCONFDIR/server.d/database.conf || exit 1
	sed -i -e "s@\(^DBName\).*@\1=$DBNAME@g" $ZABBIXCONFDIR/server.d/database.conf || exit 1
	sed -i -e "s@\(^DBUser\).*@\1=$DBUSER@g" $ZABBIXCONFDIR/server.d/database.conf || exit 1
	sed -i -e "s@\(^DBPassword\).*@\1=$DBPASSWORD@g" $ZABBIXCONFDIR/server.d/database.conf || exit 1
	echo "OK"

	echo -n "* Installing bootscripts... " >> $INSTALLLOG
	tar xf $BOOTCENTOS -C / || exit 1
	echo "OK" >> $INSTALLLOG

	echo -n "* Setting on boot... " >> $INSTALLLOG
	chkconfig --add zabbix-agentd &> /dev/null || exit 1
	chkconfig --add zabbix-server &> /dev/null || exit 1
	echo "OK" >> $INSTALLLOG

	echo -n "* Initializing... " >> $INSTALLLOG
	service zabbix-agentd start &> /dev/null || exit 1
	service zabbix-server start &> /dev/null || exit 1
	echo "OK" >> $INSTALLLOG

	echo -n "* Setting on Frontend... " >> $INSTALLLOG 
	mkdir -p /var/lib/zabbix/$VERSION
	ln -s /var/lib/zabbix/$VERSION /var/lib/zabbix/frontend
	cp -a $PKGDIR/zabbix-$VERSION/frontends/php/* /var/lib/zabbix/frontend/
	find /var/lib/zabbix/frontend/ -type d -exec chmod 0750 {} \;
	find /var/lib/zabbix/frontend/ -type f -exec chmod 0640 {} \;
	chown -R apache.apache /var/lib/zabbix/frontend/
	chmod 0770 /var/lib/zabbix/frontend/conf
cat << EOF > /etc/httpd/conf.d/zabbix-frontend.conf
<VirtualHost *:80>
	ServerAdmin webmaster@localhost.com.br

	DocumentRoot /var/lib/zabbix/frontend
	<Directory />php-bcmath
		Options FollowSymLinks
		AllowOverride None
	</Directory>
	<Directory /var/lib/zabbix/frontend>
		Options Indexes FollowSymLinks MultiViews
		AllowOverride None
		Order allow,deny
	allow from all
	</Directory>
ErrorLog /var/log/httpd/error-zabbix-frontend.log
LogLevel warn
	CustomLog /var/log/httpd/access-zabbix-frontend.log combined
</VirtualHost>
EOF

	sed -i -e 's/^max_execution_time = 30/max_execution_time = 300/g' /etc/php.ini
	sed -i -e 's/^post_max_size = 8M/post_max_size = 16M/g' /etc/php.ini
	sed -i -e 's/^max_input_time = 60/max_input_time = 300/g' /etc/php.ini
	sed -i -e 's/^;date.timezone =/date.timezone = America\/Sao_Paulo/g' /etc/php.ini
	chkconfig httpd on
	service httpd start || exit 1

	echo >> $INSTALLLOG
	echo "Installation complete. Don't forget the . /etc/profile to load the new PATH in this session" >> $INSTALLLOG
	echo >> $INSTALLLOG

	killall dialog
	dialog  --title "Instalacao Completa" --msgbox "Pressione ENTER para terminar." 0 0
	exit 0
fi




