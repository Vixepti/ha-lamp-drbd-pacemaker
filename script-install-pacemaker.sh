#!/bin/bash

echo -e "\033[33;40m------------ DEMARRAGE DU SCRIPT D INSTALLATION ------------\033[0m"

# ///////////////////////////////// CREATION DES PARTITIONS /////////////////////////////////
echo -e "\033[33;40m------------ Creation des partitions ------------\033[0m"
echo "n
p
1

+8G
n
p
2


w" | fdisk /dev/sdb

# ///////////////////////////////// CREATION CLE PUBLIQUE ET PRIVE /////////////////////////////////
echo -e "\033[33;40m------------ Creation cles ssh ------------\033[0m"
if [[ $HOSTNAME = "s-ha-web1" ]]; then
	echo -e "\033[33;40m------------ Generation de la cle ------------\033[0m"
	ssh-keygen -b 2048 -t rsa -f /root/.ssh/id_rsa -q -N ""
	echo -e "\033[33;40m------------ Copie de la cle ------------\033[0m"
	ssh-copy-id root@192.168.99.12
fi
if [[ $HOSTNAME = "s-ha-web2" ]]; then
	echo -e "\033[33;40m------------ Generation de la cle ------------\033[0m"
	ssh-keygen -b 2048 -t rsa -f /root/.ssh/id_rsa -q -N ""
	echo -e "\033[33;40m------------ Copie de la cle ------------\033[0m"
	ssh-copy-id root@192.168.99.11
fi

# /////////////////////////////////  INSTALLATION DES PAQUETS /////////////////////////////////
echo -e "\033[33;40m------------ Installation des paquets ------------\033[0m"
echo -e "\033[33;40m------------ Mise a jout des paquets ------------\033[0m"
apt update
apt upgrade -y
echo -e "\033[33;40m------------ Installation d apache2 php5 mysql-server mysql-utilities drbd8-utils ------------\033[0m"
apt install -y apache2 php5 mysql-server mysql-utilities drbd8-utils
echo -e "\033[33;40m------------ Ajout des backports ------------\033[0m"
echo "deb http://http.debian.net/debian jessie-backports main" >> /etc/apt/sources.list
echo -e "\033[33;40m------------ Installation de corosync et de pacemaker ------------\033[0m"
apt update
apt-get -t jessie-backports install corosync pacemaker crmsh -y
echo -e "\033[33;40m------------ Supression des backports ------------\033[0m"
sed -i '$d' /etc/apt/sources.list
apt update

# ///////////////////////////////// CONFIGURATION DRBD /////////////////////////////////
# ACTIVATION MODULE DRBD
echo -e "\033[33;40m------------ Activation module DRBD ------------\033[0m"
modprobe drbd
echo -e "\033[33;40m------------ Activation module DRBD Terminee ------------\033[0m"

# CREATION FICHIER CONFIG DRBD
echo -e "\033[33;40m------------ Creation configuration DRBD ------------\033[0m"
if [[ $HOSTNAME = "s-ha-web1" ]]; then
	cp mysql.res /etc/drbd.d/
	cp www.res /etc/drbd.d/
	read -p "Si l activation du module drbd est termine sur la deuxieme machine appuyer sur une touche pour continuer ..."
	scp www.res root@192.168.99.12:/etc/drbd.d/
	scp mysql.res root@192.168.99.12:/etc/drbd.d/
	echo -e "\033[33;40m------------ Copie des fichier drbd terminee ------------\033[0m"
fi

# ACTIVATION DES RESOURCES DRBD
if [[ $HOSTNAME = "s-ha-web1" ]]; then
	echo -e "\033[33;40m------------ Activation resources DRBD ------------\033[0m"
	drbdadm create-md rwww
	drbdadm up rwww
	drbdadm create-md rmysql
	drbdadm up rmysql
fi

if [[ $HOSTNAME = "s-ha-web2" ]]; then
	read -p "Si la Copie des fichier drbd terminee sur la premiere machine appuyer sur une touche pour continuer ..."
	echo -e "\033[33;40m------------ Activation resources DRBD ------------\033[0m"
	drbdadm create-md rwww
	drbdadm up rwww
	drbdadm create-md rmysql
	drbdadm up rmysql
fi

# MISE EN SERVEUR PRIMAIRE DE LA PREMIERE MACHINE
if [[ $HOSTNAME = "s-ha-web1" ]]; then
	echo -e "\033[33;40m------------ Definition du serveur DRBD primaire ------------\033[0m"
	drbdadm -- --overwrite-data-of-peer primary rwww
	drbdadm -- --overwrite-data-of-peer primary rmysql
	usrCmd=0
	while [[ $usrCmd != 1 ]]; do
		echo -e "\033[33;40m------------ Synchronisation ------------\033[0m"
		drbd-overview
		echo -e "\033[33;40m Si la Synchronisation est terminee entrez 1 sinon entrez 0 : \033[0m"
		read usrCmd
	done
	echo -e "\033[33;40m------------ Creation des filesystem ------------\033[0m"
	mkfs -t ext4 /dev/drbd0
	mkfs -t ext4 /dev/drbd1
fi

# ///////////////////////////////// CONFIGURATION MYSQL /////////////////////////////////
# CREATION DU REPERTOIRE DONNEES MYSQL
echo -e "\033[33;40m ------------ Creation du repertoire pour les donnees mysql ------------\033[0m"
mkdir /var/lib/mysql_drbd
chown mysql /var/lib/mysql_drbd
chgrp mysql /var/lib/mysql_drbd

#
if [[ $HOSTNAME = "s-ha-web1" ]]; then
	echo -e "\033[33;40m------------ Montage du peripherique drbd dans le repertoire mysql ------------\033[0m"
	mount /dev/drbd1 /var/lib/mysql_drbd
	if [[ $? != 0 ]]; then
		echo -e "\033[33;40m------------ Erreur lors du montage ------------\033[0m"
		echo -e "\033[33;40m------------ Redefinition du serveur en serveur primaire ------------\033[0m"
		drbdadm -- --overwrite-data-of-peer primary rmysql
	fi
	echo -e "\033[33;40m------------ Montage du preripherique drbd terminee ------------\033[0m"
	read -p "Appuyer sur une touche pour continuer ..."
	echo -e "\033[33;40m------------ Arret de mysql-server ------------\033[0m"
	/etc/init.d/mysql stop
	echo -e "\033[33;40m------------ Creation de la configuration mysql ------------\033[0m"
	rm /etc/mysql/my.cnf
	cp my.cnf /etc/mysql/
	echo -e "\033[33;40m------------ Configuraiton mysql drbd ------------\033[0m"
	cp /etc/mysql/my.cnf /var/lib/mysql_drbd/my.cnf
	mkdir /var/lib/mysql_drbd/data
	mysql_install_db --no-defaults --datadir=/var/lib/mysql_drbd/data --user=mysql
	chmod -R uog+rw /var/lib/mysql_drbd
	chown -R mysql /var/lib/mysql_drbd
	chmod 644 /var/lib/mysql_drbd/my.cnf
	echo -e "\033[33;40m------------ Redemarrage de mysql-server ------------\033[0m"
	/etc/init.d/mysql start
fi

if [[ $HOSTNAME = "s-ha-web2" ]]; then
	read -p "Si le Montage du peripherique drbd est terminee sur la premiere machine appuyer sur une touche pour continuer ..."
	echo -e "\033[33;40m------------ Arret de mysql-server ------------\033[0m"
	/etc/init.d/mysql stop
	echo -e "\033[33;40m------------ Creation de la configuration mysql ------------\033[0m"
	rm /etc/mysql/my.cnf
	cp my.cnf /etc/mysql/
fi

# ///////////////////////////////// CONFIGURATION APACHE /////////////////////////////////
read -p "Appuyer sur une touche pour continuer ..."
rm -rf /var/www/html/*

# ///////////////////////////////// CONFIGURATION COROSYNC /////////////////////////////////
read -p "Appuyer sur une touche pour continuer ..."
echo -e "\033[33;40m------------ Configuration de corosync ------------\033[0m"
echo -e "\033[33;40m------------ Generation de la cle d authentification ------------\033[0m"
if [[ $HOSTNAME = "s-ha-web1" ]]; then
	corosync-keygen
	chown root:root /etc/corosync/authkey
	chmod 400 /etc/corosync/authkey
	echo -e "\033[33;40m------------ Copie de la cle sur le deuxieme serveur ------------\033[0m"
	scp /etc/corosync/authkey root@192.168.99.12:/etc/corosync/authkey
	echo -e "\033[33;40m------------ Copie de la configuration de corosync ------------\033[0m"
	rm /etc/corosync/corosync.conf
	cp corosync.conf /etc/corosync/
	echo -e "\033[33;40m------------ Copie de la configuration sur le deuxieme serveur ------------\033[0m"
	scp /etc/corosync/corosync.conf root@192.168.99.12:/etc/corosync/corosync.conf
	echo -e "\033[33;40m------------ Activation du daemon ------------\033[0m"
	cp corosync /etc/default/

	echo -e "\033[33;40m------------ Redemarrage du service ------------\033[0m"
	/etc/init.d/corosync restart
	echo -e "\033[33;40m------------ Configuration de drbd terminee ------------\033[0m"
fi

if [[ $HOSTNAME = "s-ha-web2" ]]; then
	read -p "Si Configuration de drbd est termine sur la premiere machine appuyer sur une touche pour continuer ..."
	echo -e "\033[33;40m------------ Redemarrage du service ------------\033[0m"
	/etc/init.d/corosync restart
fi

# ///////////////////////////////// CONFIGURATION PACEMAKER /////////////////////////////////
read -p "Appuyer sur une touche pour continuer ..."
echo -e "\033[33;40m------------ Configuration de corosync ------------\033[0m"
if [[ $HOSTNAME = "s-ha-web1" ]]; then
	echo -e "\033[33;40m------------ Desactivation de STONITH et du QUORUM ------------\033[0m"
	crm configure property stonith-enabled=false
	crm configure property no-quorum-policy=ignore
	echo -e "\033[33;40m------------ Creation des adresses IP Virtuelles ------------\033[0m"
	crm configure primitive vipwww ocf:heartbeat:IPaddr2 params ip=192.168.100.100 cidr_netmask=24 nic="eth1" op monitor interval="30s" timeout="20s"
	crm configure primitive vipmysql ocf:heartbeat:IPaddr2 params ip=192.168.100.101 cidr_netmask=24 nic="eth1" op monitor interval="30s" timeout="20s"
	echo -e "\033[33;40m------------ Ajout du service apache2 ------------\033[0m"
	crm configure primitive httpd ocf:heartbeat:apache params configfile="/etc/apache2/apache2.conf" op start timeout="60s" op stop timeout="60s" op monitor timeout="20s"
	echo -e "\033[33;40m------------ Ajout resources DRBD ------------\033[0m"
	crm configure primitive Drbdwww ocf:linbit:drbd params drbd_resource="rwww" op monitor interval="30s" role="Slave" op monitor interval="29s" role="Master"
	crm configure primitive DrbdMysql ocf:linbit:drbd params drbd_resource="rmysql" op monitor interval="30s" role="Slave" op monitor interval="29s" role="Master"
	echo -e "\033[33;40m------------ Ajout resource fs DRBD ------------\033[0m"
	crm configure primitive fsDrbdwww ocf:heartbeat:Filesystem params device="/dev/drbd0" directory="/var/www/html" fstype="ext4" op monitor interval="30s" timeout="30s"
	crm configure primitive fsDrbdMysql ocf:heartbeat:Filesystem params device="/dev/drbd1" directory="/var/lib/mysql_drbd" fstype="ext4" op monitor interval="30s" timeout="30s"
	echo -e "\033[33;40m------------ Ajout du service mysql ------------\033[0m"
	crm configure primitive mysql ocf:heartbeat:mysql params binary="/usr/sbin/mysqld" config="/var/lib/mysql_drbd/my.cnf" datadir="/var/lib/mysql_drbd/data" pid="/var/run/mysqld/mysqld.pid" socket="/var/run/mysqld/mysqld.sock" user="mysql" group="mysql" additional_parameters="--bind-address=localhost" op start timeout="120s" interval="0" op stop timeout="120s" interval="0" op monitor interval="20s" timeout="30s"
	echo -e "\033[33;40m------------ Creation des groupes ------------\033[0m"
	crm configure group gwww fsDrbdwww vipwww httpd
	crm configure group gmysql fsDrbdMysql vipmysql mysql
	echo -e "\033[33;40m------------ Creation resources Master - Slave ------------\033[0m"
	crm configure ms ms_drbdwww Drbdwww meta master-max="1" master-node-max="1" clone-max="2" clone-node-max="1" notify="true"
	crm configure ms ms_drbdMysql DrbdMysql meta master-max="1" master-node-max="1" clone-max="2" clone-node-max="1" notify="true"	
	echo -e "\033[33;40m------------ Creation colocations ------------\033[0m"
	crm configure colocation cl_gwww-with-drbdwww inf: gwww ms_drbdwww:Master
	crm configure colocation cl_gmysql-with-drbdMysql inf: gmysql ms_drbdMysql:Master
	echo -e "\033[33;40m------------ Configuration priorite ------------\033[0m"
	crm configure order o_drbdwww-before-gwww inf: ms_drbdwww:promote gwww:start
	crm configure order o_drbdMysql-before-gmysql inf: ms_drbdMysql:promote gmysql:start
	echo -e "\033[33;40m------------ Configuration de corosync Terminee ------------\033[0m"
	read -p "Appuyer sur une touche pour continuer ..."
	crm_mon
fi

if [[ $HOSTNAME = "s-ha-web2" ]]; then
	read -p "Si Configuration de corosync Terminee sur la premiere machine appuyer sur une touche pour continuer ..."
	crm_mon
fi