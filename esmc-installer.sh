#!/usr/bin/env bash
# ESET Security Management Center Installer

#############
# VARIABLES #
#############

script_name=`basename $0`
script_version="1.0"
source /etc/os-release

tomcat_url="https://apache.osuosl.org/tomcat/tomcat-9/v9.0.40/bin/apache-tomcat-9.0.40.tar.gz"
ESMC_server_url="https://download.eset.com/com/eset/apps/business/era/server/linux/latest/server-linux-x86_64.sh"
ESMC_web_console_url="https://download.eset.com/com/eset/apps/business/era/webconsole/latest/era.war"
ESMC_rdsensor_url="https://download.eset.com/com/eset/apps/business/era/rdsensor/latest/rdsensor-linux-x86_64.sh"

if [[ "$VERSION_ID" == "16.04" ]]; then 
  odbc_url=https://downloads.mysql.com/archives/get/p/10/file/mysql-connector-odbc-8.0.17-linux-ubuntu16.04-x86-64bit.tar.gz
elif [[ "$VERSION_ID" == "18.04" ]]; then 
  odbc_url=https://downloads.mysql.com/archives/get/p/10/file/mysql-connector-odbc-8.0.17-linux-ubuntu18.04-x86-64bit.tar.gz
elif [[ "$VERSION_ID" == "20.04" ]]; then 
  odbc_url=https://downloads.mysql.com/archives/get/p/10/file/mysql-connector-odbc-8.0.17-linux-ubuntu18.04-x86-64bit.tar.gz
fi


#############
# FUNCTIONS #
#############

function verify_root()
{
    #Verify running as root
    ROOT_UID=0    
    if [ "`id -u`" != $ROOT_UID ]; then
        echo "You don't have sufficient privileges to run this script. Please run it with sudo."
        exit 1
    fi
    clear
}

function download_packages()
{
    echo ""
    echo "Downloading components..."
    echo ""

    if `test ! -s $(basename $ESMC_server_url)`; then
        wget --connect-timeout 300 --no-check-certificate "$ESMC_server_url" || curl -O --fail --connect-timeout 300 -k "$ESMC_server_url" &
    fi

    if `test ! -s $(basename $ESMC_web_console_url)`; then
        wget --connect-timeout 300 --no-check-certificate "$ESMC_web_console_url" || curl -O --fail --connect-timeout 300 -k "$ESMC_web_console_url" &
    fi

    if `test ! -s $(basename $ESMC_rdsensor_url)`; then
        wget --connect-timeout 300 --no-check-certificate "$ESMC_rdsensor_url" || curl -O --fail --connect-timeout 300 -k "$ESMC_rdsensor_url" &
    fi

    if `test ! -s $(basename $tomcat_url)`; then
        wget --connect-timeout 300 --no-check-certificate "$tomcat_url" || curl -O --fail --connect-timeout 300 -k "$tomcat_url" &
    fi

    if `test ! -s $(basename $odbc_url)`; then
        wget --connect-timeout 300 --no-check-certificate "$odbc_url" || curl -O --fail --connect-timeout 300 -k "$odbc_url" &
    fi

    echo ""
    echo "Components finished downloading"
    echo ""
}

function install_mysql() 
{
    echo ""
    echo "Installing MySQL Server 8..."
    echo ""
    # This repo is distribution specific and needs logic added for switching xenial, bionic, focal cases
    echo "deb http://repo.mysql.com/apt/ubuntu/ "$UBUNTU_CODENAME" mysql-8.0" > /etc/apt/sources.list.d/mysql.list

    if test -s /etc/apt/sources.list.d/mysql.list; then
        apt update
        debconf-set-selections <<< "mysql-community-server mysql-community-server/root-pass password eraadmin"
        debconf-set-selections <<< "mysql-community-server mysql-community-server/re-root-pass password eraadmin"
        DEBIAN_FRONTEND=noninteractive apt-get -y install mysql-server unixodbc
    fi 

    STR=`mysql --version`
    SUB="mysql  Ver 8"
    if [[ "$STR" == *"$SUB"* ]]; then

    echo "[mysqld]" >> /etc/mysql/my.cnf
    echo "log_bin_trust_function_creators=1" >> /etc/mysql/my.cnf
    echo "innodb_log_file_size=100M" >> /etc/mysql/my.cnf
    echo "innodb_log_files_in_group=2" >> /etc/mysql/my.cnf

    systemctl start mysql &
    echo ""
    echo "Finished Installing MySQL Server 8"
    echo ""
    fi
}

function uninstall_mysql() 
{
    apt-get remove -y mysql-server
    apt-get -y autoremove
    rm -f /etc/apt/sources.list.d/mysql.list
    # Any mysql packages installed? 
    # dpkg -l | grep mysql | grep ii | wc -l
    mysql --version 

    if [[ "$?" != 0 ]]; then
    echo ""
    echo "Finished Uninstalling MySQL Server 8"
    echo ""
    fi
}

function install_mysql_odbc()
{
    if `test -f /etc/odbcinst.ini`; then
      echo ""
      echo "Installing MySQL ODBC Driver..."
      echo ""
      if `test -s $(basename $odbc_url)`; then
        tar xzvf $(basename $odbc_url)
        cd $(basename ${odbc_url%.*.*}) 
        cp ./bin/* /usr/local/bin/
        cp ./lib/* /usr/local/lib/
        myodbc-installer -a -d -n "MySQL ODBC 8.0 Driver" -t "Driver=/usr/local/lib/libmyodbc8w.so"
      fi
      echo ""
      echo "Done"
      echo ""
    fi
}

function uninstall_mysql_odbc()
{
    if `test -s /etc/odbcinst.ini`; then
      echo ""
      echo "Uninstalling MySQL ODBC Driver..."
      echo ""
    fi
    myodbc-installer -r -d -n "MySQL ODBC 8.0 Driver"
    if `test -s /usr/local/lib/libmyodbc8S.so`; then
      rm -f /usr/local/lib/libmyodbc8S.so
    fi
    if `test -s /usr/local/lib/libmyodbc8w.so`; then
      rm -f /usr/local/lib/libmyodbc8w.so
    fi
    if `test -s /usr/local/lib/libmyodbc8a.so`; then
      rm -f /usr/local/lib/libmyodbc8a.so
    fi
    if `test -s /usr/local/bin/myodbc-installer`; then
      rm -f /usr/local/bin/myodbc-installer
    fi
      echo ""
      echo "Done"
      echo ""
}

function install_java()
{
    java -version
    if [[ "$?" != 0 ]]; then 
        echo ""
        echo "Installing Java"
        echo ""
        apt -y install default-jdk
    else
        echo "Java is already installed"
    fi 
}

function create_systemd_service_file() 
{
    if test -s /etc/systemd/system/multi-user.target.wants/tomcat.service; then
        echo "Tomcat service file already exists. Is tomcat already installed?"
        return 10
    else
        echo '[Unit]' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'Description=Apache Tomcat Web Application Container' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'After=network.target' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo '' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo '[Service]' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'Type=forking' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo '' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'Environment="JAVA_HOME=/usr/lib/jvm/default-java"' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'Environment="JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom"' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo '' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'Environment="CATALINA_PID=/usr/share/tomcat/temp/tomcat.pid"' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'Environment="CATALINA_HOME=/usr/share/tomcat"' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'Environment="CATALINA_BASE=/usr/share/tomcat"' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC"' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        
        echo '' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'ExecStart=/usr/share/tomcat/bin/startup.sh' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'ExecStop=/usr/share/tomcat/bin/shutdown.sh' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo '' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'User=tomcat' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'Group=tomcat' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'UMask=0007' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'RestartSec=10' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'Restart=always' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo '' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo '[Install]' >> /etc/systemd/system/multi-user.target.wants/tomcat.service
        echo 'WantedBy=multi-user.target' >> /etc/systemd/system/multi-user.target.wants/tomcat.service

        return 0;
    fi
}

function install_tomcat()
{
    install_java
    groupadd tomcat
    useradd -s /bin/false -g tomcat -d /usr/share/tomcat tomcat
    mkdir /usr/share/tomcat
    tar xzvf apache-tomcat-*tar.gz -C /usr/share/tomcat --strip-components=1
    cd /usr/share/tomcat
    chgrp -R tomcat /usr/share/tomcat
    chown -RH tomcat /usr/share/tomcat
    chmod -R g+r conf
    chmod g+x conf
    create_systemd_service_file
    systemctl daemon-reload
    systemctl start tomcat
    systemctl enable tomcat
    echo ""
    echo "Tomcat has been installed"
    echo ""
}

function uninstall_tomcat()
{
    systemctl stop tomcat 
    rm -Rf /usr/share/tomcat/
    rm -f /etc/systemd/system/multi-user.target.wants/tomcat.service
    systemctl daemon-reload
    userdel tomcat
    echo ""
    echo "Tomcat has been uninstalled"
    echo ""
}

function install_esmc_server()
{
  echo ""
  echo "Installing ESMC Server..."
  echo ""
  chmod +x ./server-linux-x86_64.sh
  ./server-linux-x86_64.sh \
  --skip-license \
  --db-type="MySQL Server" \
  --db-driver="MySQL ODBC 8.0 Driver" \
  --db-hostname=localhost \
  --db-port=3306 \
  --db-admin-username=root \
  --db-admin-password=eraadmin \
  --server-root-password=eraadmin \
  --db-user-username=root \
  --db-user-password=eraadmin \
  --cert-hostname="*"
}

function print_usage()
{
    cat <<EOF
    Usage: $(basename $0) [options]

    Options:
    -h, --help                                   [optional] print this help message
    -v, --version                                [optional] print product version
    -d, --download-packages......................[optional] download ESMC components 
    -m, --install-mysql..........................[optional] install MySQL
    -M, --uninstall-mysql........................[optional] uninstall MySQL
    -o, --install-mysql..........................[optional] install MySQL ODBC connector
    -O, --uninstall-mysql........................[optional] uninstall MySQL ODBC connector
    -t, --install-tomcat.........................[optional] install tomcat
    -T, --uninstall-tomcat.......................[optional] uninstall tomcat
    -s, --install-esmc-server....................[optional] install ESMC server

    --hostname=                                  server hostname for connecting to the server (hostname, IPv4, IPv6 or service record)
    --port=                                      server port for connecting (not needed if service record was provided), default is '2222'

EOF
}

function print_version()
{
  echo "ESET Security Management Center Installer (version: $script_version), Copyright © 1992-2020 ESET, spol. s r.o. - All rights reserved."
  echo ""
}

###################
# PARSE ARGUMENTS #
###################

while test $# != 0
do
  case "$1" in
    -h|--help)
      print_usage
      exit 0
      ;;
    -v|--version)
      print_version
      exit 0
      ;;
    -d|--download-packages)
      download_packages
      exit 0
      ;;
    -m|--install-mysql)
      verify_root
      install_mysql
      exit 0
      ;;
    -M|--uninstall-mysql)
      verify_root
      uninstall_mysql
      exit 0
      ;;
    -o|--install-odbc)
      verify_root
      install_mysql_odbc
      exit 0
      ;;
    -O|--uninstall-odbc)
      verify_root
      uninstall_mysql_odbc
      exit 0
      ;;
    -t|--install-tomcat)
      verify_root
      install_tomcat
      exit 0
      ;;
    -T|--uninstall-tomcat)
      verify_root
      uninstall_tomcat
      exit 0
      ;;
    -s|--install-esmc-server)
      verify_root
      install_esmc_server
      exit 0
      ;;
    *)
      echo "Unknown option \"$1\". Run '$script_name --help' for usage information." >&2
      exit 1
      ;;
  esac
  shift
done










