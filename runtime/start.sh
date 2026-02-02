#!/opt/bin/bash

echo "Enabling swap"
swapon /user-resource/swapfile

echo 201 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio201/direction
echo "Turning off bed..."
echo 0 > /sys/class/gpio/gpio201/value
#echo 201 > /sys/class/gpio/unexport

echo 140 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio140/direction
echo "Turning off hotend..."
echo 0 > /sys/class/gpio/gpio140/value
#echo 140 > /sys/class/gpio/unexport

sleep 2

#echo 201 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio201/direction
echo "Turning on bed..."
echo 1 > /sys/class/gpio/gpio201/value
#echo 201 > /sys/class/gpio/unexport

#echo 140 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio140/direction
echo "Turning on hotend..."
echo 1 > /sys/class/gpio/gpio140/value
#echo 140 > /sys/class/gpio/unexport

sleep 3

echo "Booting firmware on hotend..."
/app/mcu-flasher --skip --no-wait /dev/serial/by-id/usb-ShenZhenCBD_STM32_Virtual_ComPort_*-if00

echo "Booting firmware on bed..."
/app/mcu-flasher --skip --no-wait /dev/ttyS4

sleep 1

#echo "Booting firmware on hotend (again)..."
#/app/mcu-flasher --skip --no-wait /dev/serial/by-id/usb-ShenZhenCBD_STM32_Virtual_ComPort_*-if00

# TODO: Remove log
/app/dsp-to-serial > /user-resource/dsptoserial.log 2>&1 &

sleep 2

#echo "Starting klipper"
#python3 /user-resource/experiments/klippy/klippy.py /user-resource/experiments/printer_data/config/printer-elegoo-centauri-carbon-1.cfg -a /tmp/klippy_uds1 -l /user-resource/klippy.log &

echo "Starting moonraker"
PATH=/user-resource/experiments/bin:$PATH /user-resource/experiments/moonraker/moonraker-env/bin/python /user-resource/experiments/moonraker/moonraker/moonraker/moonraker.py  -d /user-resource/experiments/printer_data 2>&1 > /user-resource/moonraker.log &
