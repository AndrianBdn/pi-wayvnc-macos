#!/bin/sh
# Wayvnc service launcher used by pi-wayvnc-macos.
# Mirrors /usr/sbin/wayvnc-run.sh but invokes /opt/pi-wayvnc-macos/bin/wayvnc
# (and the matching wayvncctl, to avoid mixed IPC versions).

PREFIX=/opt/pi-wayvnc-macos

# Sourced for $XKBMODEL / $XKBLAYOUT — same as stock RPi wrapper.
[ -r /etc/default/keyboard ] && . /etc/default/keyboard

export XDG_RUNTIME_DIR=/tmp/wayvnc
mkdir -p "$XDG_RUNTIME_DIR"

export XKB_DEFAULT_MODEL="${XKBMODEL:-}"
export XKB_DEFAULT_LAYOUT="${XKBLAYOUT:-}"

SELF_PID=$$

# Background readiness watcher: poll our wayvncctl until it answers, then
# notify systemd that the service is up.
{
    while ! "$PREFIX/bin/wayvncctl" --socket=/tmp/wayvnc/wayvncctl.sock version >/dev/null 2>&1; do
        sleep 0.1
    done
    systemd-notify --ready --pid=$SELF_PID
} &

# Mirror stock wrapper's CMA hint for non-Pi5 hardware.
if command -v raspi-config >/dev/null 2>&1 && ! raspi-config nonint is_pifive ; then
    export WAYVNC_CMA=/dev/dma_heap/linux,cma
fi

"$PREFIX/bin/wayvnc" --detached \
    --gpu \
    --config /etc/wayvnc/config \
    --socket /tmp/wayvnc/wayvncctl.sock
