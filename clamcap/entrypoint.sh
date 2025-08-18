#!/bin/sh
if [ -e /run/clamav/clamd.sock ]; then
	rm /run/clamav/clamd.sock
fi

if [ ! -e /var/lib/clamav/main.cvd ]; then
	freshclam
fi

freshclam -d -c 6 &
clamd &

while [ ! -e /run/clamav/clamd.sock ]; do
	sleep 5
done

/usr/local/c-icap/bin/c-icap -N -D &

pids=`jobs -p`

exitcode=0

terminate() {
    for pid in $pids; do
        if ! kill -0 $pid 2>/dev/null; then
            wait $pid
            exitcode=$?
        fi
    done
    kill $pids 2>/dev/null
}

trap terminate CHLD
wait

exit $exitcode
