## Requirements
- Raspberry Pi 3b
- Raspberry Pi OS 32bit
- OpenOCD for STM32F030 programming
- ST-Link v2 or compatible programmer

## Description
This folder contains a tool for headless production programming of STM32F030 ICs with GameKit firmware. It consists of 1 shell script, 1 service and several OpenOCD configuration files. The service runs the infinite-loop script, which executes the following steps: 
1. Wait for STM32F030 target detection via OpenOCD (target connection check)
2. Flash GameKit Firmware to STM32F030 using OpenOCD
3. Light up green ACT led and GPIO status LEDs
4. Wait for tests to be done and disconnection of STM32F030

## Raspberry Pi Preparation Steps:
- create Raspberry Pi OS 32bit (port of debian bullseye, 2023-05-03) with user "pi", choose password, internet connection not necessary
- install OpenOCD: `sudo apt install openocd`
- get control of ACT led in /boot/config.txt by adding to the bottom:
```
dtparam=act_led_trigger=none
dtparam=act_led_activelow=off
```
- clone this repo
- copy service to systemd with `sudo cp prodprog.service /lib/systemd/system/`
- reload services with `sudo systemctl daemon-reload`
- enable service with `sudo systemctl enable prodprog.service`
- start service with `sudo systemctl start prodprog.service`

## Exchange firmware files: 
- GameKit Firmware (STM32F030): modify APPLICATION_FW variable in prodprog.sh

## Hardware Setup
### ST-Link v2 -> STM32F030: 
-  VCC -> STM32F030 3.3V
-  SWDIO -> STM32F030 SWDIO pin
-  SWCLK -> STM32F030 SWCLK pin
-  GND -> STM32F030 GND
-  RST -> STM32F030 RESET pin (optional)

### RPI GPIO -> Status LEDs:
- GPIO 21 -> IF_DONE_LED (Interface programming done)
- GPIO 7 -> APP_DONE_LED (Application programming done)

## Configuration Files
- `stm32f030_config.cfg` - Main OpenOCD configuration for STM32F030
- `detect_target.cfg` - Target detection script
- `flash_gamekit.cfg` - GameKit firmware flashing script

## Monitoring
- `systemctl status prodprog.service` - To check if service is started
- `journalctl -f -u prodprog.service` - To see console output of service
- `prodprog.log` contains minimal logging info of production-programming
- `detect.log` contains info of last target detection
- `flash.log` contains info of last firmware flashing operation

## Key Changes from Calliope Mini Version
- Replaced JLink commands with OpenOCD commands
- Removed NRF52820 recovery step (not needed for STM32F030)
- Removed USB mass storage mounting (direct flash programming)
- Simplified to single-stage firmware flashing
- Updated target detection for STM32F030 specific responses
- Maintained GPIO LED control for Raspberry Pi status indication