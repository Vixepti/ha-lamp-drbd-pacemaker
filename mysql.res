resource rmysql {
	syncer {
		rate 100M;
	}

	on s-ha-web1 {
		device /dev/drbd1;
		disk /dev/sdb2;
		address 192.168.102.1:7789;
		meta-disk internal;
	}

	on s-ha-web2 {
		device /dev/drbd1;
		disk /dev/sdb2;
		address 192.168.102.2:7789;
		meta-disk internal;
	}
}

