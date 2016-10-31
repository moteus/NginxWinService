# NginxWinService
Service wrappers for `nginx` and `php-cgi` for Windows

## Support

### nginx
 * restart `master` process
 * close master process using `stop` signal
 * terminate all child processes if they not terminated with master process
 * log rotatae once per day

### php
 * run multiple PHP processes on different ports
 * restart PHP process
