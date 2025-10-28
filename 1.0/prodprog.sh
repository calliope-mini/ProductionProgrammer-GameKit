#!/bin/bash

APPLICATION_FW="GameKitF030C8.hex"
COUNT=0

# Color definitions
MAG='\x1b[35;49;1m'
RED='\x1b[39;41;1m'
DEF='\x1b[39;49m'
GRE='\x1b[32;49m'


# Debug environment info
printf "${MAG}=== Environment Debug ===${DEF}\n"
printf "User: $(whoami)\n"
printf "Groups: $(groups)\n" 
printf "USB devices: $(lsusb | grep -i st)\n"
printf "OpenOCD path: $(which openocd)\n"
printf "Working directory: $(pwd)\n"
printf "${MAG}=== End Environment Debug ===${DEF}\n"



# Make internal ACT led accessible
sudo chmod 666 /sys/class/leds/ACT/brightness
sudo chmod 666 /sys/class/leds/PWR/brightness

echo 1 >/sys/class/leds/ACT/brightness  # Turn on ACT LED


while true; do # Main production loop
    while true; do # Inner loop for error recovery
        echo 1 > /sys/class/leds/PWR/brightness  # Turn off red power LED
        TARGET_DETECTED=0
        FLASHED=0
        
        # Wait for STM32F030 target detection
        while true; do
            printf "${MAG}START - Waiting for STM32F030 target${DEF}\n"
            START=$SECONDS
            
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
                elif grep -q "open failed" detect.log; then
                    printf "${RED}STM32F030: ST-Link open failed - USB permission issue${DEF}\n"
                else
                    printf "${RED}STM32F030 target not detected: Connect STM32F030${DEF}\n"
                fi
                # Show the actual OpenOCD output for debugging
                printf "${MAG}=== OpenOCD Debug Output ===${DEF}\n"
                cat detect.log
                printf "${MAG}=== End Debug Output ===${DEF}\n"
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
            echo 0 > /sys/class/leds/PWR/brightness  # Turn on red power LED
            
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
