resource rwww {
	syncer {
		rate 100M;
	}
	
	on s-ha-web1 {
		device /dev/drbd0;
		disk /dev/sdb1;
		address 192.168.102.1:7788;
		meta-disk internal;
	}

	on s-ha-web2 {
		device /dev/drbd0;
		disk /dev/sdb1;
		address 192.168.102.2:7788;
		meta-disk internal;
	}
}
