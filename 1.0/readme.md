## Requirements
- Raspberry Pi 
- STLink 
- openocd V0.12

- udevrule 
- sudo usermod -a -G dialout $USER


## Raspberry Pi Preparation Steps:
- get control of ACT led in /boot/config.txt by adding to the bottom:
dtparam=act_led_trigger=none
dtparam=act_led_activelow=off
- clone this repo
- copy service to systemd with sudo cp prodprog.service /lib/systemd/system/
- reload services with sudo systemctl daemon-reload
- enable service with sudo systemctl enable prodprog.service
- start service with sudo systemctl start prodprog.service

## Exchange firmware files: 
- replace GameKitF030C8.hex

## Hardware Setup
- The Raspberry Pi connects to the STM32F030C8 by a STLink-V3MINIE via TagConnect (SWD).
- The pinout is:
  - 1 VCC
  - 2 SWDIO
  - 3 RESET (unused)
  - 4 SWCLK
  - 5 GND
  - 6 Empty
- VTarget of the STLink is shortened to VCC and therefore set to permanent high
- VCC is taken from a pad of the capacitor next to the LDO (3.3V!) 


## Monitoring
- systemctl status prodprog.service
  - To check if service is started
- journalctl -f -u prodprog.service
  - To see console output of service
- prodprog.log contains minimal logging info of production-programming
