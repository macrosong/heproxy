kill -9 `ps -ef| grep heproxy.pl | grep -v grep| awk '{print(" "+$2);}'`