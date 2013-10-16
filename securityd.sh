#!/bin/bash
#
# Securityd is based on zonex.sh 
# zonex is a sample bridge between mochad and ZoneMinder. Modify it to suit
# your needs.
#
# zonex looks for X10 events from mochad. When it receives an alert from a
# DS10A door/window sensor, zonex turns lights on by sending commands to
# mochad. Next zonex sends a trigger to ZoneMinder to tell it to start
# recording.
#
# Here is what a DS10A event from mochad looks like.  03/15 12:00:35 Rx RFSEC
# Addr: BB:AA:00 Func: Contact_alert_max_DS10A
#
# My ZoneMinder cameras are set to Nodect which means no video motion
# detection.  The cameras are all triggered X10 sensors.
#
# You may need to modify zmtrigger.pl to disable serial port monitoring and
# enable TCP monitoring.
#
# --
# Modified by Ken Tarwood to track sensor and alarm arming states. Also extended script to deal with larger number of sensors and keychain remotes.
# The script will perform a number of tasks including sending alerts to zoneminder when security events occur.
# Note that new security addresses are generated by DS10A sensors when batteries are removed!
#
# Example event from KR10a Security Remote
# 10/06 22:39:57 Rx RFSEC Addr: 7A:52:81 Func: Arm_KR10A

MOCHADHOST=localhost
MOCHADPORT=1099

ZMHOST=localhost
ZMPORT=6802

EMAILRECIPIENTS="me@mydomain.com"
EMAILSUBJECT="** Security Sensor State Change **"
EMAILFROM="noreply@mydomain.com"

# Track arming status
ISARMED=false

# Associative array of sensor locations and addresses
declare -A SENSORS
SENSORS["X1:XX:XX"]="Front Door"
SENSORS["X2:XX:XX"]="Patio Door"
#SENSORS[""]="Basement Door"
#SENSORS[""]="Front Garage Bay"
#SENSORS[""]="Rear Garage Bay"
SENSORS["X3:XX:XX"]="Kitchen Patio Window"

# Associative array of sensor states (we need to keep track of them since sensors ping occasionally when left open)
declare -A STATES
STATES["X1:XX:XX"]="unknown"
STATES["X2:XX:XX"]="unknown"
#STATES[""]="unknown"
#STATES[""]="unknown"
#STATES[""]="unknown"
STATES["X3:XX:XX"]="unknown"

# Send a ZoneMinder trigger
zmtrigger() {
    echo "$@" >/dev/tcp/${ZMHOST}/${ZMPORT}
}

# Connect TCP socket to mochad on handle 6.
exec 6<>/dev/tcp/${MOCHADHOST}/${MOCHADPORT}

# Read X10 events from mochad
while read <&6
do
	# Show the line on standard output just for debugging.
	#echo ${REPLY} >&1

	# Extract the sensor address if possible
	ADDRESS=$(grep -o -m2 "[0-9A-F]\{2\}\(:[0-9A-F]\{2\}\)\{2\}" <<<"${REPLY}" | tail -1)

    	case ${REPLY} in
        *Rx\ RFSEC\ Addr:\ *\ Func:\ Contact_alert_*DS10A)
		if [ ${STATES[$ADDRESS]}!="open" ] && $ISARMED
		then
			# Door/window open
			# TODO: Note battery state!
			# Start recording on camera 2 for 60 seconds
			#zmtrigger "5|on+10|255|${SENSORS[$ADDRESS]} Open|${SENSORS[$ADDRESS]} Open"

			ALERT="${SENSORS[$ADDRESS]} is Open in armed state"
			echo $ALERT >&1
			flite -t $ALERT

			MAIL="subject:$EMAILSUBJECT\nfrom:$EMAILFROM\n${SENSORS[$ADDRESS]} has opened."
			echo -e $MAIL | /usr/sbin/sendmail "$EMAILRECIPIENTS"
		fi

		STATES[$ADDRESS]="open"
        ;;
        *Rx\ RFSEC\ Addr:\ *\ Func:\ Contact_normal_*DS10A)
		if [ ${STATES[$ADDRESS]}!="closed" ] && $ISARMED
		then
			# Door/window closed

			echo "${SENSORS[$ADDRESS]} is Closed" >&1

                        MAIL="subject:$EMAILSUBJECT\nfrom:$EMAILFROM\n${SENSORS[$ADDRESS]} has closed."
                        echo -e $MAIL | /usr/sbin/sendmail "$EMAILRECIPIENTS"
		fi

		STATES[$ADDRESS]="closed"
        ;;
	*Rx\ RFSEC\ Addr:\ *\ Func:\ Arm_KR10A)
		if !($ISARMED)
		then
			# Ensure no sensors are currently tripped before arming

			# System is armed
			ALERT="System is now armed"
			echo $ALERT
			flite -t $ALERT

			ISARMED=true
		fi
	;;
	*Rx\ RFSEC\ Addr:\ *\ Func:\ Disarm_KR10A)
		if $ISARMED
		then
			# System is disarmed
			ALERT="System is now disarmed."
			echo $ALERT
			flite -t $ALERT

			ISARMED=false

			# TODO: Kill any ongoing alarms
		fi
	;;
    esac
done
