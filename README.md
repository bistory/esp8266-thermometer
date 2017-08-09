# ESP8266 Thermometer

A simple project based on the ESP8266 and the SHT21 temperature and humidity sensor.

## Installation / dependencies

Go to NodeMCU-Build(http://nodemcu-build.com/) and download a firmware with ADC, end user setup, file, GPIO, I²C, net, node, RTC fifo, RTC mem, RTC Time, SNTP, timer, UART and WiFi.

Flash your ESP with it the float one then upload the init file of this project using ESPlorer.

This program uses deepsleep to don't forget to wire GPIO0 and RST to enable it.

## Usage

Update SSID and SSID_PASSWORD according to your WiFi settings, THINGSPEAK_CHANNEL and THINGSPEAK_KEY with the channel ID and the API key of ThingSpeak.

When powered, the device will send data to ThingSpeak once every half hour then will sleep.

## Todo

I'm planning to implement end user setup.
