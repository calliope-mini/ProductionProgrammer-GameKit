#!/bin/bash

APPLICATION_FW="GameKitF030C8.hex"
COUNT=0

# Color definitions
MAG='\x1b[35;49;1m'
RED='\x1b[39;41;1m'
DEF='\x1b[39;49m'
GRE='\x1b[32;49m'

# LEDs on Header on GPIO 18 and 19 (more compatible with Pi 4)
IF_DONE_LED=18
APP_DONE_LED=19

# Utility function to export a pin if not already exported
exportPin() {
  if [ ! -e /sys/class/gpio/gpio$1 ]; then
    # Try to export with sudo for Pi 4 compatibility
    echo "$1" | sudo tee /sys/class/gpio/export >/dev/null 2>&1
    # Wait a bit and retry if it failed
    if [ ! -e /sys/class/gpio/gpio$1 ]; then
      sleep 0.2
      echo "$1" | sudo tee /sys/class/gpio/export >/dev/null 2>&1
    fi
    # Make it accessible to the user
    if [ -e /sys/class/gpio/gpio$1 ]; then
      sudo chown $USER:$USER /sys/class/gpio/gpio$1/direction 2>/dev/null
      sudo chown $USER:$USER /sys/class/gpio/gpio$1/value 2>/dev/null
    fi
  fi
}

# Utility function to set a pin as an output
setOutput() {
  if [ -e /sys/class/gpio/gpio$1/direction ]; then
    echo "out" > /sys/class/gpio/gpio$1/direction
  else
    printf "${RED}Warning: GPIO$1 not available${DEF}\n"
  fi
}

# Utility function to change state of a light
setLightState() {
  if [ -e /sys/class/gpio/gpio$1/value ]; then
    echo $2 > /sys/class/gpio/gpio$1/value
  fi
}

# Initialize GPIO pins
exportPin $IF_DONE_LED
exportPin $APP_DONE_LED
# Give time for GPIO export to complete
sleep 0.1
setOutput $IF_DONE_LED
setOutput $APP_DONE_LED

# Make internal ACT led accessible
sudo chmod 666 /sys/class/leds/ACT/brightness

while true; do # Main production loop
    while true; do # Inner loop for error recovery
        echo 0 > /sys/class/leds/ACT/brightness  # Turn off green ACT LED
        TARGET_DETECTED=0
        FLASHED=0
        
        # Wait for STM32F030 target detection
        while true; do
            printf "${MAG}START - Waiting for STM32F030 target${DEF}\n"
            START=$SECONDS
            setLightState $APP_DONE_LED 0
            setLightState $IF_DONE_LED 0
            
            # Check if STM32F030 target is connected and responsive
            openocd -f interface/stlink.cfg -f target/stm32f0x.cfg -c "adapter speed 400; init; targets; exit" >detect.log 2>&1
            TARGET_DETECTED=$(grep -c "Cortex-M0.*processor detected\|Examination succeed" detect.log)
            
            if ((TARGET_DETECTED > 0)); then 
                printf "${GRE}STM32F030 target detected${DEF}\n"
                break
            else 
                # Check if it's a voltage issue
                if grep -q "target voltage may be too low" detect.log; then
                    printf "${RED}STM32F030: Target voltage too low - check power connection${DEF}\n"
                elif grep -q "unable to connect to the target" detect.log; then
                    printf "${RED}STM32F030: Unable to connect - check SWD connections${DEF}\n"
                else
                    printf "${RED}STM32F030 target not detected: Connect STM32F030${DEF}\n"
                fi
                sleep 1
            fi
        done
        
        # Unlock and Flash GameKit Firmware to STM32F030
        printf "${MAG}Unlocking STM32F030${DEF}\n"
        openocd -f interface/stlink.cfg -f target/stm32f0x.cfg -c "adapter speed 400; init; reset halt; stm32f0x unlock 0; exit" > unlock.log 2>&1
        
        printf "${MAG}Start flashing STM32F030 with GameKit firmware${DEF}\n"
        openocd -f interface/stlink.cfg -f target/stm32f0x.cfg -c "adapter speed 400; init; reset halt; flash write_image erase $APPLICATION_FW; verify_image $APPLICATION_FW; reset run; exit" > flash.log 2>&1
        FLASHED=$(grep -c "flash size\|wrote.*bytes\|verified.*bytes\|Examination succeed" flash.log)
        
        if (( FLASHED > 0 )); then 
            printf "${GRE}STM32F030: GameKit firmware flashed successfully${DEF}\n"
            setLightState $IF_DONE_LED 1
            setLightState $APP_DONE_LED 1
            echo 1 > /sys/class/leds/ACT/brightness  # Turn on green ACT LED
            
            # Calculate elapsed time and log success
            ELAPSED=$(($SECONDS - $START))
            printf "${GRE}SUCCESS: Programming done in ${ELAPSED} seconds${DEF}\n"
            
            # Log programming success
            DATETIME=$(date "+%Y.%m.%d %H:%M:%S")
            COUNT=$((COUNT + 1))
            echo "$DATETIME $COUNT $ELAPSED" >> prodprog.log
            
        else 
            printf "${RED}STM32F030: flashing failed${DEF}\n"
            echo "=== DEBUG: Flash log contents ==="
            cat flash.log
            echo "=== END DEBUG ==="
            sleep 1
            break  # Restart the process
        fi
        
        # Wait for STM32F030 disconnection
        printf "${MAG}Test and disconnect STM32F030${DEF}\n"
        while true; do
            openocd -f interface/stlink.cfg -f target/stm32f0x.cfg -c "adapter speed 400; init; targets; exit" >detect.log 2>&1
            TARGET_DETECTED=$(grep -c "Cortex-M0.*processor detected\|Examination succeed" detect.log)
            
            if ((TARGET_DETECTED > 0)); then 
                sleep 1  # Still connected, wait
            else 
                printf "${GRE}STM32F030 disconnected${DEF}\n"
                break
            fi
        done
        
        break  # Everything successful, start anew
    done
done
