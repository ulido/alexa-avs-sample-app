#!/bin/bash

#-------------------------------------------------------
# Paste from developer.amazon.com below
#-------------------------------------------------------

# This is the name given to your device or mobile app in the Amazon developer portal. To look this up, navigate to https://developer.amazon.com/edw/home.html. It may be labeled Device Type ID.
ProductID=YOUR_PRODUCT_ID_HERE

# Retrieve your client ID from the web settings tab within the developer console: https://developer.amazon.com/edw/home.html
ClientID=YOUR_CLIENT_ID_HERE

# Retrieve your client secret from the web settings tab within the developer console: https://developer.amazon.com/edw/home.html
ClientSecret=YOUR_CLIENT_SECRET_HERE

#-------------------------------------------------------
# No need to change anything below this...
#-------------------------------------------------------

#-------------------------------------------------------
# Pre-populated for testing. Feel free to change.
#-------------------------------------------------------

# Your Country. Must be 2 characters!
Country='US'
# Your state. Must be 2 or more characters.
State='WA'
# Your city. Cannot be blank.
City='SEATTLE'
# Your organization name/company name. Cannot be blank.
Organization='AVS_USER'
# Your device serial number. Cannot be blank, but can be any combination of characters.
DeviceSerialNumber='123456789'
# Your KeyStorePassword. We recommend leaving this blank for testing.
KeyStorePassword=''

#-------------------------------------------------------
# Inserts user-provided values into a template file
#-------------------------------------------------------
# Arguments are: template_directory, template_name, target_name
use_template()
{
  Template_Loc=$1
  Template_Name=$2
  Target_Name=$3
  while IFS='' read -r line || [[ -n "$line" ]]; do
    while [[ "$line" =~ (\$\{[a-zA-Z_][a-zA-Z_0-9]*\}) ]]; do
      LHS=${BASH_REMATCH[1]}
      RHS="$(eval echo "\"$LHS\"")"
      line=${line//$LHS/$RHS}
    done
    echo "$line" >> "$Template_Loc/$Target_Name"
  done < "$Template_Loc/$Template_Name"
}

# Preconfigured variables
OS=rpi
User=$(id -un)
Group=$(id -gn)
Origin=$(pwd)
Samples_Loc=$Origin/samples
Java_Client_Loc=$Samples_Loc/javaclient
Wake_Word_Agent_Loc=$Samples_Loc/wakeWordAgent
Companion_Service_Loc=$Samples_Loc/companionService
Kitt_Ai_Loc=$Wake_Word_Agent_Loc/kitt_ai
Sensory_Loc=$Wake_Word_Agent_Loc/sensory
External_Loc=$Wake_Word_Agent_Loc/ext
Locale="en-US"

mkdir $Kitt_Ai_Loc
mkdir $Sensory_Loc
mkdir $External_Loc

Locale="en-US"
sudo amixer cset numid=3 1

Wake_Word_Detection_Enabled="true"

echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | sudo /usr/bin/debconf-set-selections
chmod +x $Java_Client_Loc/install-java8.sh
cd $Java_Client_Loc && bash ./install-java8.sh
cd $Origin

echo "========== Getting the code for Kitt-Ai ==========="
cd $Kitt_Ai_Loc
git clone https://github.com/Kitt-AI/snowboy.git

echo "========== Getting the code for Sensory ==========="
cd $Sensory_Loc
git clone https://github.com/Sensory/alexa-rpi.git

cd $Origin

echo "========== Downloading and Building Port Audio Library needed for Kitt-Ai Snowboy =========="
cd $Kitt_Ai_Loc/snowboy/examples/C++
bash ./install_portaudio.sh
sudo ldconfig
cd $Kitt_Ai_Loc/snowboy/examples/C++
make -j4
sudo ldconfig
cd $Origin

echo "========== Generating ssl.cnf =========="
if [ -f $Java_Client_Loc/ssl.cnf ]; then
  rm $Java_Client_Loc/ssl.cnf
fi
use_template $Java_Client_Loc template_ssl_cnf ssl.cnf

echo "========== Generating generate.sh =========="
if [ -f $Java_Client_Loc/generate.sh ]; then
  rm $Java_Client_Loc/generate.sh
fi
use_template $Java_Client_Loc template_generate_sh generate.sh

echo "========== Executing generate.sh =========="
chmod +x $Java_Client_Loc/generate.sh
cd $Java_Client_Loc && bash ./generate.sh
cd $Origin

echo "========== Configuring Companion Service =========="
if [ -f $Companion_Service_Loc/config.js ]; then
  rm $Companion_Service_Loc/config.js
fi
use_template $Companion_Service_Loc template_config_js config.js

echo "========== Configuring Java Client =========="
if [ -f $Java_Client_Loc/config.json ]; then
  rm $Java_Client_Loc/config.json
fi
use_template $Java_Client_Loc template_config_json config.json

echo "========== Configuring ALSA Devices =========="
if [ -f /home/$User/.asoundrc ]; then
  rm /home/$User/.asoundrc
fi
printf "pcm.!default {\n  type asym\n   playback.pcm {\n     type plug\n     slave.pcm \"hw:0,0\"\n   }\n   capture.pcm {\n     type plug\n     slave.pcm \"hw:1,0\"\n   }\n}" >> /home/$User/.asoundrc

echo "========== Installing Java Client =========="
if [ -f $Java_Client_Loc/pom.xml ]; then
  rm $Java_Client_Loc/pom.xml
fi
cp $Java_Client_Loc/pom_pi.xml $Java_Client_Loc/pom.xml
cd $Java_Client_Loc && mvn validate && mvn install && cd $Origin

echo "========== Installing Companion Service =========="
cd $Companion_Service_Loc && npm install && cd $Origin

echo "========== Preparing External dependencies for Wake Word Agent =========="
mkdir $External_Loc/include
mkdir $External_Loc/lib
mkdir $External_Loc/resources

cp $Kitt_Ai_Loc/snowboy/include/snowboy-detect.h $External_Loc/include/snowboy-detect.h
cp $Kitt_Ai_Loc/snowboy/examples/C++/portaudio/install/include/portaudio.h $External_Loc/include/portaudio.h
cp $Kitt_Ai_Loc/snowboy/examples/C++/portaudio/install/include/pa_ringbuffer.h $External_Loc/include/pa_ringbuffer.h
cp $Kitt_Ai_Loc/snowboy/examples/C++/portaudio/install/include/pa_util.h $External_Loc/include/pa_util.h
cp $Kitt_Ai_Loc/snowboy/lib/$OS/libsnowboy-detect.a $External_Loc/lib/libsnowboy-detect.a
cp $Kitt_Ai_Loc/snowboy/examples/C++/portaudio/install/lib/libportaudio.a $External_Loc/lib/libportaudio.a
cp $Kitt_Ai_Loc/snowboy/resources/common.res $External_Loc/resources/common.res
cp $Kitt_Ai_Loc/snowboy/resources/alexa/alexa-avs-sample-app/alexa.umdl $External_Loc/resources/alexa.umdl

sudo ln -s /usr/lib/atlas-base/atlas/libblas.so.3 $External_Loc/lib/libblas.so.3

$Sensory_Loc/alexa-rpi/bin/sdk-license file $Sensory_Loc/alexa-rpi/config/license-key.txt $Sensory_Loc/alexa-rpi/lib/libsnsr.a $Sensory_Loc/alexa-rpi/models/spot-alexa-rpi-20500.snsr $Sensory_Loc/alexa-rpi/models/spot-alexa-rpi-21000.snsr $Sensory_Loc/alexa-rpi/models/spot-alexa-rpi-31000.snsr
cp $Sensory_Loc/alexa-rpi/include/snsr.h $External_Loc/include/snsr.h
cp $Sensory_Loc/alexa-rpi/lib/libsnsr.a $External_Loc/lib/libsnsr.a
cp $Sensory_Loc/alexa-rpi/models/spot-alexa-rpi-31000.snsr $External_Loc/resources/spot-alexa-rpi.snsr

mkdir $Wake_Word_Agent_Loc/tst/ext
cp -R $External_Loc/* $Wake_Word_Agent_Loc/tst/ext
cd $Origin

echo "========== Compiling Wake Word Agent =========="
cd $Wake_Word_Agent_Loc/src && cmake . && make -j4
cd $Wake_Word_Agent_Loc/tst && cmake . && make -j4

chown -R $User:$Group $Origin
chown -R $User:$Group /home/$User/.asoundrc

echo ""
echo '============================='
echo '*****************************'
echo '========= Finished =========='
echo '*****************************'
echo '============================='
echo ""

Number_Terminals=2
if [ "$Wake_Word_Detection_Enabled" = "true" ]; then
  Number_Terminals=3
fi
echo "To run the demo, do the following in $Number_Terminals seperate terminals:"
echo "Run the companion service: cd $Companion_Service_Loc && npm start"
echo "Run the AVS Java Client: cd $Java_Client_Loc && mvn exec:exec"
if [ "$Wake_Word_Detection_Enabled" = "true" ]; then
  echo "Run the wake word agent: "
  echo "  Sensory: cd $Wake_Word_Agent_Loc/src && ./wakeWordAgent -e sensory"
  echo "  KITT_AI: cd $Wake_Word_Agent_Loc/src && ./wakeWordAgent -e kitt_ai"
  echo "  GPIO: PLEASE NOTE -- If using this option, run the wake word agent as sudo:"
  echo "  cd $Wake_Word_Agent_Loc/src && sudo ./wakeWordAgent -e gpio"
fi
