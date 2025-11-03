#!/bin/bash

# Configuration constants
readonly APPLICATION_FW="GameKitF030C8.hex"
readonly ADAPTER_SPEED=400
readonly DETECT_RETRY_DELAY=1
readonly OPERATION_TIMEOUT=30
readonly MAX_CONSECUTIVE_FAILURES=3

COUNT=0
CONSECUTIVE_FAILURES=0

# Color definitions
MAG='\x1b[35;49;1m'
RED='\x1b[39;41;1m'
DEF='\x1b[39;49m'
GRE='\x1b[32;49m'


check_raspberry_pi() {
    local is_rpi=false
    # Method 1: Check /proc/device-tree/model (most reliable for RPi)
    if [[ -f /proc/device-tree/model ]] && grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null; then
        is_rpi=true
        printf "${GRE}✓ Running on Raspberry Pi${DEF}\n"
        if [[ -f /proc/device-tree/model ]]; then
            printf "Model: $(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')\n"
        fi
        return 0
    fi
        return 1
}

# Safety checks before starting production
printf "${MAG}=== Production Safety Checks ===${DEF}\n"

# Check if firmware file exists and is not empty
if [[ ! -f "$APPLICATION_FW" ]]; then
    printf "${RED}ERROR: Firmware file $APPLICATION_FW not found${DEF}\n"
    exit 1
fi

if [[ ! -s "$APPLICATION_FW" ]]; then
    printf "${RED}ERROR: Firmware file $APPLICATION_FW is empty${DEF}\n"
    exit 1
fi

if [[ ! -r "$APPLICATION_FW" ]]; then
    printf "${RED}ERROR: Firmware file $APPLICATION_FW is not readable${DEF}\n"
    exit 1
fi

printf "${GRE}✓ Firmware file validated: $APPLICATION_FW${DEF}\n"

# Check if OpenOCD is available
if ! command -v openocd >/dev/null 2>&1; then
    printf "${RED}ERROR: OpenOCD is not installed or not in PATH${DEF}\n"
    exit 1
fi

printf "${GRE}✓ OpenOCD found: $(which openocd)${DEF}\n"

# Check LED access (non-fatal if not available)
LED_ACCESS=true
if check_raspberry_pi; then
    if ! sudo chmod 666 /sys/class/leds/ACT/brightness 2>/dev/null; then
        printf "${RED}Warning: Cannot access ACT LED - continuing without LED status${DEF}\n"
        LED_ACCESS=false
    fi

    if ! sudo chmod 666 /sys/class/leds/PWR/brightness 2>/dev/null; then
        printf "${RED}Warning: Cannot access PWR LED - continuing without LED status${DEF}\n"
        LED_ACCESS=false
    fi
    # Update PATH for OpenOCD
    export PATH="$(pwd)/xpack-openocd/bin:$PATH"

fi


if $LED_ACCESS; then
    printf "${GRE}✓ LED access configured${DEF}\n"
fi

printf "${MAG}=== Safety checks completed - Starting production ===${DEF}\n"


# Debug environment info
printf "${MAG}=== Environment Debug ===${DEF}\n"
printf "User: $(whoami)\n"
printf "Groups: $(groups)\n" 
printf "USB devices: $(lsusb | grep -i st)\n"
printf "OpenOCD path: $(which openocd)\n"
printf "Working directory: $(pwd)\n"
printf "${MAG}=== End Environment Debug ===${DEF}\n"



# Set initial LED state if available
if $LED_ACCESS; then
    echo 1 >/sys/class/leds/ACT/brightness  # Turn on ACT LED to indicate ready
fi


while true; do # Main production loop
    while true; do # Inner loop for error recovery
        if $LED_ACCESS; then
            echo 1 > /sys/class/leds/PWR/brightness  # Turn off red power LED
        fi
        TARGET_DETECTED=0
        FLASHED=0
        
        # Wait for STM32F030 target detection
        while true; do
            printf "${MAG}START - Waiting for STM32F030 target${DEF}\n"
            START=$SECONDS
            
            # Check if STM32F030 target is connected and responsive
            openocd -f interface/stlink.cfg -c "transport select swd" -f target/stm32f0x.cfg -c "adapter speed $ADAPTER_SPEED; init; targets; exit" >detect.log 2>&1
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
        openocd -f interface/stlink.cfg -c "transport select swd" -f target/stm32f0x.cfg -c "adapter speed $ADAPTER_SPEED; init; reset halt; stm32f0x unlock 0; exit" > unlock.log 2>&1
        
        printf "${MAG}Start flashing STM32F030 with GameKit firmware${DEF}\n"
        openocd -f interface/stlink.cfg -c "transport select swd" -f target/stm32f0x.cfg -c "adapter speed $ADAPTER_SPEED; init; reset halt; flash write_image erase $APPLICATION_FW; verify_image $APPLICATION_FW; reset run; exit" > flash.log 2>&1
        FLASHED=$(grep -c "flash size\|wrote.*bytes\|verified.*bytes\|Examination succeed" flash.log)
        
        if (( FLASHED > 0 )); then 
            printf "${GRE}STM32F030: GameKit firmware flashed successfully${DEF}\n"
            if $LED_ACCESS; then
                echo 0 > /sys/class/leds/PWR/brightness  # Turn on red power LED
            fi
            
            # Calculate elapsed time and log success
            ELAPSED=$(($SECONDS - $START))
            printf "${GRE}SUCCESS: Programming done in ${ELAPSED} seconds${DEF}\n"
            
            # Reset consecutive failures counter on success
            CONSECUTIVE_FAILURES=0
            
            # Log programming success
            DATETIME=$(date "+%Y.%m.%d %H:%M:%S")
            COUNT=$((COUNT + 1))
            echo "$DATETIME $COUNT $ELAPSED" >> prodprog.log
            
        else 
            printf "${RED}STM32F030: flashing failed${DEF}\n"
            echo "=== DEBUG: Flash log contents ==="
            cat flash.log
            echo "=== END DEBUG ==="
            
            # Increment consecutive failures counter
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            printf "${RED}Consecutive failures: $CONSECUTIVE_FAILURES/$MAX_CONSECUTIVE_FAILURES${DEF}\n"
            
            # Exit if too many consecutive failures (hardware issue likely)
            if (( CONSECUTIVE_FAILURES >= MAX_CONSECUTIVE_FAILURES )); then
                printf "${RED}ERROR: Too many consecutive failures ($MAX_CONSECUTIVE_FAILURES). Exiting to prevent damage.${DEF}\n"
                printf "${RED}Check hardware connections, power supply, and ST-Link adapter.${DEF}\n"
                exit 1
            fi
            
            sleep 1
            break  # Restart the process
        fi
        
        # Wait for STM32F030 disconnection
        printf "${MAG}Test and disconnect STM32F030${DEF}\n"
        while true; do
            openocd -f interface/stlink.cfg -c "transport select swd" -f target/stm32f0x.cfg -c "adapter speed $ADAPTER_SPEED; init; targets; exit" >detect.log 2>&1
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
