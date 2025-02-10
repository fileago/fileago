#!/bin/sh
erl -name dms@127.0.0.1 -setcookie ${SECRETCOOKIE} -pa /dms/deps/*/ebin /dms/ebin -s dms
