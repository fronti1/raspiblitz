#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# config script to connect mobile apps with lnd connect"
 echo "# will autodetect dyndns, sshtunnel or TOR"
 echo "# bonus.lndconnect.sh [zap-ios|zap-android|zeus-ios|zeus-android|shango-ios|shango-android]"
 exit 1
fi

# load raspiblitz config data
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

#### PARAMETER

# 1. TARGET WALLET
targetWallet=$1 

# 1. REST or RPC
# determine service port from argument
if [ "$1" == "RPC" ]; then
  echo "# RPC mode"
  servicePort="10009"
fi
if [ "$1" == "REST" ]; then
  echo "# REST mode"
  servicePort="8080"
fi

# 2. FORCE NOCERT (optional)
if [ "$2" == "NOCERT" ]; then
  echo "# forcing NOCERT"
  extraparamter="--nocert"
elif [ "$2" == "SHANGO" ]; then
  echo "# connecting thru shango QR code"
  connector="shango"
fi

#### MAKE SURE LNDCONNECT IS INSTALLED

# check if it is installed
# https://github.com/rootzoll/lndconnect
# using own fork of lndconnet because of this commit to fix for better QR code:
commit=e76226f2dd3cce3c169a7161f66612c2662407fa
isInstalled=$(lndconnect -h 2>/dev/null | grep "nocert" -c)
if [ $isInstalled -eq 0 ] || [ "$1" == "update" ]; then
  echo "# Installing lndconnect.."
  # make sure Go is installed
  /home/admin/config.scripts/bonus.go.sh
  # get Go vars
  source /etc/profile
  # Install latest lndconnect from source:
  go get -d github.com/rootzoll/lndconnect
  cd $GOPATH/src/github.com/rootzoll/lndconnect
  //git checkout $commit
  make
else
  echo "# lndconnect is already installed" 
fi

#### ADAPT PARAMETERS BASED TARGETWALLET 

# defaults
connector=""
host=""
port=""
extraparamter=""
supportsTOR=0

if [ "${targetWallet}" = "zap-ios" ]; then

  connector="lndconnect"
  supportsTOR=0 # deactivated until fix: https://github.com/rootzoll/raspiblitz/issues/1001
  
  if [ "${runBehindTor}" == "on" ] && [ ${supportsTOR} -eq 1 ]; then
    # when ZAP runs on TOR it uses REST
    port="8080"
    extraparamter="--nocert"
  else
    # normal ZAP uses gRPC ports
    port="10009"
  fi
  
elif [ "${targetWallet}" = "zap-android" ]; then

  connector="lndconnect"
  supportsTOR=1
  if [ "${runBehindTor}" == "on" ] && [ ${supportsTOR} -eq 1 ]; then
    # when ZAP runs on TOR it uses REST
    port="8080"
    extraparamter="--nocert"
  else
    # normal ZAP uses gRPC ports
    port="10009"
  fi

elif [ "${targetWallet}" = "zeus-ios" ]; then

  connector="lndconnect"
  supportsTOR=0
  port="8080"

elif [ "${targetWallet}" = "zeus-android" ]; then

  connector="lndconnect"
  supportsTOR=1
  port="8080"

elif [ "${targetWallet}" = "shango-ios" ]; then

  connector="shango"
  supportsTOR=0
  port="10009"

elif [ "${targetWallet}" = "shango-android" ]; then

  connector="shango"
  supportsTOR=0
  port="10009"

else
  echo "error='unknown target wallet'"
  exit 1
fi

#### ADAPT PARAMETERS BASED RASPIBLITZ CONFIG

# get the local IP as default host
host=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

# change host to dynDNS if set
if [ ${#dynDomain} -gt 0 ]; then
  host="${dynDomain}"
fi

# tunnel thru TOR if running and supported by the wallet
if [ "${runBehindTor}" == "on" ] && [ ${supportsTOR} -eq 1 ]; then
  # depending on RPC or REST use different TOR address
  if [ "${port}" == "10009" ]; then
    host=$(sudo cat /mnt/hdd/tor/lndrpc10009/hostname)
    port="10009"
    echo "# using TOR --> host ${host} port ${port}"
  elif [ "${port}" == "8080" ]; then
    host=$(sudo cat /mnt/hdd/tor/lndrest8080/hostname)
    port="8080"
    echo "# using TOR --> host ${host} port ${port}"
  fi
fi
  
# tunnel thru SSH-Reverse-Tunnel if activated for that port
if [ ${#sshtunnel} -gt 0 ]; then
  isForwarded=$(echo ${sshtunnel} | grep -c "${port}<")
  if [ ${isForwarded} -gt 0 ]; then
    if [ "${port}" == "10009" ]; then
      host=$(echo $sshtunnel | cut -d '@' -f2 | cut -d ' ' -f1 | cut -d ':' -f1)
      port=$(echo $sshtunnel | awk '{split($0,a,"10009<"); print a[2]}' | cut -d ' ' -f1 | sed 's/[^0-9]//g')
      echo "# using ssh-tunnel --> host ${host} port ${port}"
    elif [ "${port}" == "8080" ]; then
      host=$(echo $sshtunnel | cut -d '@' -f2 | cut -d ' ' -f1 | cut -d ':' -f1)
      port=$(echo $sshtunnel | awk '{split($0,a,"8080<"); print a[2]}' | cut -d ' ' -f1 | sed 's/[^0-9]//g')
      echo "# using ssh-tunnel --> host ${host} port ${port}"
    fi
  fi
fi

#### RUN LNDCONNECT

imagePath=""
datastring=""

if [ "${connector}" == "lndconnect" ]; then

  # get Go vars
  source /etc/profile

  # write qr code data to an image
  cd /home/admin
  lndconnect --host=${host} --port=${port} --image ${extraparamter}

  # display qr code image on LCD
  /home/admin/config.scripts/blitz.lcd.sh image /home/admin/lndconnect-qr.png

elif [ "${connector}" == "shango" ]; then

  # write qr code data to text file
  datastring=$(echo -e "${host}:${port},\n$(xxd -p -c2000 /home/admin/.lnd/data/chain/${network}/${chain}net/admin.macaroon),\n$(openssl x509 -sha256 -fingerprint -in /home/admin/.lnd/tls.cert -noout)")

  # display qr code on LCD
  /home/admin/config.scripts/blitz.lcd.sh qr "${datastring}"

else
  echo "error='unkown connector'"
  exit 1
fi

# show pairing info dialog
msg=""
if [ $(echo "${host}" | grep -c '192.168') -gt 0 ]; then
  msg="Make sure you are on the same local network.\n(WLAN same as LAN - use WIFI not cell network on phone).\n\n"
fi
msg="You should now see the pairing QR code on the RaspiBlitz LCD.\n\n${msg}When you start the App choose to connect to your own node.\n(DIY / Remote-Node / lndconnect)\n\nClick on the 'Scan QR' button. Scan the QR on the LCD and <continue> or <show QR code> to see it in this window."
whiptail --backtitle "Connecting Mobile Wallet" \
	 --title "Pairing by QR code" \
	 --yes-button "continue" \
	 --no-button "show QR code" \
	 --yesno "${msg}" 18 65
if [ $? -eq 1 ]; then
  if [ "${connector}" == "lndconnect" ]; then
    lndconnect --host=${host} --port=${port} ${extraparamter}
    echo "(To shrink QR code: OSX->CMD- / LINUX-> CTRL-) Press ENTER when finished."
    read key
  elif [ "${connector}" == "shango" ]; then
    /home/admin/config.scripts/blitz.lcd.sh qr-console ${datastring}
  fi
fi

# clean up
/home/admin/config.scripts/blitz.lcd.sh hide
shred ${imagePath} 2> /dev/null
rm -f ${imagePath} 2> /dev/null

echo "------------------------------"
echo "If the connection was not working:"
if [ ${#dynDomain} -gt 0 ]; then
  echo "- Make sure that your router is forwarding port ${port} to the Raspiblitz"
fi
if [ $(echo "${host}" | grep -c '192.168') -gt 0 ]; then
  echo "- Check that your WIFI devices can talk to the LAN devices on your router (deactivate IP isolation or guest mode)."
fi
echo "- try to refresh the TLS & macaroons: Main Menu 'EXPORT > 'RESET'"
echo "- check issues: https://github.com/rootzoll/raspiblitz/issues"
echo ""