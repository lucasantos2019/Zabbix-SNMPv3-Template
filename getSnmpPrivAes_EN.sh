#!/bin/bash
# Author:	Igor A. Silkin
# Date:		Jan, 2019
# Description:	Getting Cisco switch and routers IOS version, interfaces's state, monitoring temperature, cooler, uptime 
#		by SNMPv3 value through snmpwalk utility

function getSwitchTemperature {
	local resValue

	if [[ $1 -eq 1 ]]; then
		resValue="OK"
	elif [[ $1 -eq 2 ]]; then
		resValue="High!"
	elif [[ $1 -eq 3 ]]; then
		resValue="Critical!"
	fi
	echo $resValue
}

function getCoolerState {
	local arg
	local coolerValue=""
	local coolerNumber=0

	for arg in $*
	do
		coolerNumber=$(( $coolerNumber + 1 ))
		if [[ "$arg" -eq 1 ]]; then
			coolerValue+="Status of cooler $coolerNumber: # OK\n"
		elif [[ "$arg" -eq 2 ]]; then
			coolerValue+="Status of cooler $coolerNumber: # Some problem!\n"
		elif [[ "$arg" -eq 3 ]]; then
			coolerValue+="Status of cooler $coolerNumber: # Invalid!\n"
		elif [[ "$arg" -eq 4 ]]; then
			coolerValue+="Status of cooler $coolerNumber: # Shutdown\n"
		elif [[ "$arg" -eq 5 ]]; then
			coolerValue+="Status of cooler $coolerNumber: # Not present\n"
		elif [[ "$arg" -eq 3 ]]; then
			coolerValue+="Status of cooler $coolerNumber: # No working\n"
		fi
	done
	echo $coolerValue
}

function getStackTemperature {
	local arg
	local stackTemperature=""
	local switchNum=0

	for arg in $*
	do
		switchNum=$(( $switchNum + 1 ))
		stackTemperature+="Temperature sensor $switchNum: # $arg"
		stackTemperature+=$(echo -e "\u00b0""C")
		stackTemperature+="\n"
	done
	echo $stackTemperature
}

function insertColSeparate {
        local index
        local item

        index=0
        for item in $* #${!intfValue[*]}
        do
                intfValue[index]+="#"$item
                index=$(( $index + 1 ))
        done
}

function insertEndLine {
        local index
        for index in ${!intfValue[*]}
        do
                intfValue[index]+="\n"
        done
}

function getReturnValue {
        local index
        local retValue

        retValue="Interface#Admin status#Oper. status#VLAN\n"
        for index in ${!intfValue[*]}
        do
                retValue+=${intfValue[index]}
        done
        echo $retValue
}

function getVlanNumber {
	local item
	local indexIntf=0
	local indexTrunk
	local indexVlan
	local intfVlan

	for item in $*;	do
		intfVlan=""
		# check port trunk
		indexTrunk=0
		while [ $indexTrunk -lt ${#arrTrunk[*]} ]
		do
			if [[ ${arrTrunk[$indexTrunk]} = $item ]]; then
				intfVlan=${arrTrunk[$indexTrunk + 1]}
				if [[ $intfVlan == 1 ]];then
					intfVlan="trunk"
					break
				else
					intfVlan="n/a"
					break
				fi

			fi
			indexTrunk=$(( $indexTrunk + 2 ))
		done

		if [[ $intfVlan == "" ]]; then
			intfVlan="n/a"
		fi

		# get port VLAN number
		indexVlan=0
		while [ $indexVlan -lt ${#arrVLAN[*]} ]
		do
                        if [[ ${arrVLAN[$indexVlan]} = $item ]]; then
                                intfVlan=${arrVLAN[$indexVlan + 1]}
				break
                        fi
			indexVlan=$(( $indexVlan + 2 ))
                done

		intfValue[indexIntf]+="#"$intfVlan
		indexIntf=$(( $indexIntf + 1 ))
	done
}

# check args
if [[ ($1 != "") && ($2 != "") && ($3 != "") && ($4 != "") ]]; then
	# get IOS version
	iosVersion=$(snmpwalk -v3 -a SHA -A $1 -l authPriv -u $2 -x aes -X $3 $4 1.3.6.1.2.1.1.1.0)
	iosVersion=$(echo $iosVersion | awk '{print $7,$8,$9,$10,$11}' | sed 's/.$//g')
	result=$(echo 'IOS version: #' $iosVersion "\n")

	# get IOS flash
	iosFlash=$(snmpwalk -v3 -a SHA -A $1 -l authPriv -u $2 -x aes -X $3 $4 1.3.6.1.2.1.16.19.6.0 | awk '{print $4}' | sed 's/^.//g' | sed 's/.$//g')
	result+=$(echo 'IOS file: #' $iosFlash "\n")

	# get uptime
	uptime=$(snmpwalk -v3 -a SHA -A $1 -l authPriv -u $2 -x aes -X $3 $4 1.3.6.1.2.1.1.3.0 | awk -F ')' '{print $2}' | sed -e 's/^.//')
#	if [[ $uptime == *"days"*  ]]; then
#		intDay=$(echo $uptime | awk '{print $1}')
#		strDay=$(GetDays $intDay)
#		uptime=$(echo $uptime | sed 's/days/'$strDay'/')
#	fi

	result+=$(echo 'Uptime: #' $uptime "\n")

	# get cooler state
	cooler=$(snmpwalk -v3 -a SHA -A $1 -l authPriv -u $2 -x aes -X $3 $4 1.3.6.1.4.1.9.9.13.1.4.1.3)
	if [[ $cooler == *"No Such"* ]]; then
		cooler=$(snmpwalk -v3 -a SHA -A $1 -l authPriv -u $2 -x aes -X $3 $4 1.3.6.1.4.1.9.9.13.1.3.1.3) 
		if [[ $cooler != *"No Such"* ]]; then
			cooler=$(snmpwalk -v3 -a SHA -A $1 -l authPriv -u $2 -x aes -X $3 $4 1.3.6.1.4.1.9.9.13.1.3.1.3 | awk '{print $4}')
	                coolerValue=$(getStackTemperature $cooler)
		fi
	else
		cooler=$(echo $cooler | awk '{print $4}')
		coolerValue=$(getCoolerState $cooler)

	fi
	result+=$(echo $coolerValue)

	# get temperature
	temperature=$(snmpwalk -v3 -a SHA -A $1 -l authPriv -u $2 -x aes -X $3 $4 1.3.6.1.4.1.9.5.1.2.13)
	temperatureValue=""

	if [[ $temperature == *"No Such Object"* ]]; then
		temperatureValue=$(snmpwalk -v3 -a SHA -A $1 -l authPriv -u $2 -x aes -X $3 $4 1.3.6.1.4.1.9.9.13.1.3.1.3 | awk '{print $4}')
		temperatureValue+=$(echo -e "\u00b0""C")
	else
		args=$(echo $temperature | awk '{print $4}')
		temperatureValue=$(getSwitchTemperature $args)
	fi

	result+=$(echo 'Temperature: #' $temperatureValue "\n")

	# get interface status
	adminStatus=$(snmpwalk -v3 -a SHA -A $1 -l authPriv -u $2 -x aes -X $3 $4 IF-MIB::ifAdminStatus | awk '{print $4}' | sed "s/([0-9])//")
	operStatus=$(snmpwalk -v3 -a SHA -A $1 -l authPriv -u $2 -x aes -X $3 $4 IF-MIB::ifOperStatus | awk '{print $4}' | sed "s/([0-9])//")
	intfDescr=$(snmpwalk -v3 -a SHA -A $1 -l authPriv -u $2 -x aes -X $3 $4 IF-MIB::ifDescr | awk '{print $4}')
	intfIndex=$(snmpwalk -v3 -a SHA -A $1 -l authPriv -u $2 -x aes -X $3 $4 IF-MIB::ifIndex | awk '{print $4}') 

	# get ports trunk status
        strTrunk=$(snmpwalk -v3 -a SHA -A $1 -l authPriv -u $2 -x aes -X $3 $4 1.3.6.1.4.1.9.9.46.1.6.1.1.14 | awk '{print $1,$4}' | cut -d . -f 15)
        arrTrunk=( $strTrunk )

	# get ports VLAN
        strVLAN=$(snmpwalk -v3 -a SHA -A $1 -l authPriv -u $2 -x aes -X $3 $4 1.3.6.1.4.1.9.9.68.1.2.2.1.2 | awk '{print $1,$4}' | cut -d . -f 15)
        arrVLAN=( $strVLAN )

	intfValue=( $intfDescr )

	insertColSeparate $adminStatus
	insertColSeparate $operStatus
	getVlanNumber $intfIndex

	insertEndLine
	returnValue=$(getReturnValue)

	# output result
	echo -e $result | column -s '#' -t
	echo -e "\nInterfaces status:\n"
	echo -e $returnValue | column -s '#' -t
fi
