#!/usr/bin/env bash

server_pid=""
sub1_pid=""
sub2_pid=""
pub1_pid=""
pub2_pid=""

loadtest_terminate_program() {
  echo "terminating: $1"
  if [[ -n "$1" ]]; then
    kill -2 "$1"
  fi
  sleep 1
  if [[ $(kill -0 "$1" &> /dev/null) ]]; then
    kill -9 "$1"
  fi
}

loadtest_cleanup() {
  echo "cleaning up"

  loadtest_terminate_program "$pub1_pid"
  loadtest_terminate_program "$pub2_pid"
  loadtest_terminate_program "$sub1_pid"
  loadtest_terminate_program "$sub2_pid"
  loadtest_terminate_program "$server_pid"

}

loadtest_error_handler() {
  loadtest_cleanup
  exit 1
}

trap loadtest_cleanup SIGINT
trap loadtest_error_handler ERR

echo "Starting server"
./zig-out/bin/loadtest_server &
server_pid=$!

sleep 1

echo "Starting subs"
./zig-out/bin/loadtest_sub1 &
sub1_pid=$!
./zig-out/bin/loadtest_sub2 &
sub2_pid=$!

sleep 1

echo "Starting pubs"
./zig-out/bin/loadtest_pub1 &
pub1_pid=$!
./zig-out/bin/loadtest_pub2 &
pub2_pid=$!

# loop until the sub programs come down
while [[ $(kill -0 "$sub1_pid" &> /dev/null) || $(kill -0 "$sub2_pid" &> /dev/null) ]]; do
  echo "loop"
  sleep 1
done

loadtest_cleanup
