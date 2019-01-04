#!/usr/bin/python
from BaseHTTPServer import HTTPServer, BaseHTTPRequestHandler
from SocketServer import ThreadingMixIn
import threading
import atexit
import sys
import syslog
import os
from sys import exit
import json
import syslog
import traceback
from signal import signal, SIGTERM

HOSTNAME = "0.0.0.0"
HOST_PORT =  8081

class Handler(BaseHTTPRequestHandler):
    def process_health_check(self):
	return True

    def do_GET(self):
        if (self.process_health_check()):
            self.send_response(200)
        else:
            self.send_error(500)
        self.end_headers()
#        message =  threading.currentThread().getName()
#        self.wfile.write(message)
#        self.wfile.write('\n')
        return

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    """Handle requests in a separate thread."""
    def __init__(self, t, handler):
        #self._ThreadedHTTPServer__is_shut_down.set()
        HTTPServer.__init__(self, t, handler)
        check_lock_file('/var/run/health-webserver.pid', 'health-webserver')


def check_lock_file(lockfile='/var/lock/filename',procname='procname'):
	if os.access(lockfile, os.F_OK):
		#if the lockfile is already there then check the PID number
		#in the lock file
		pidfile = open(lockfile, "r")
		pidfile.seek(0)
		old_pid = pidfile.readline()
		# Now we check the PID from lock file matches to the current
		# process PID
		if os.path.exists("/proc/%s" % old_pid):
			syslog.syslog(syslog.LOG_WARN, "You already have an instance of " + procname + " running")
			syslog.syslog(syslog.LOG_WARN, procname + " is running as process %s," % old_pid)
			sys.exit(1)
		else:
			syslog.syslog(syslog.LOG_WARN, "Stale lock file being removed:  " + lockfile)
			os.remove(os.path(lockfile))
			subprocess.check_call(['rm', lockfile])

        #create pid/lock file
	pidfile = open(lockfile, "w")
	pidfile.write("%s" % os.getpid())
	pidfile.close()

def cleanup():
	syslog.syslog(syslog.LOG_INFO, "health-webserver exit handler")
	os.remove("/var/run/health-webserver.pid")
	syslog.syslog(syslog.LOG_INFO, "health-webserver lock removed")


if __name__ == '__main__':
    try:
        port = HOST_PORT
        if "HEALTH_WEBSERVER_PORT" in os.environ:
            port = os.environ['HEALTH_WEBSERVER_PORT']
        server = ThreadedHTTPServer((HOSTNAME, port), Handler)
        syslog.syslog(syslog.LOG_INFO, 'Starting server, use SIGTERM to stop')
        atexit.register(cleanup)
        # Normal exit when killed
        signal(SIGTERM, lambda signum, stack_frame: exit(1))
        server.serve_forever()
    except KeyboardInterrupt:
        print ('Exiting...')
