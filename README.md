# ESP8266 Thermometer

A simple project based on the ESP8266 and the DHT22 temperature and humidity sensor.

## Installation / dependencies

Go to NodeMCU-Build(http://nodemcu-build.com/) and download a firmware with ADC, DHT, file, GPIO, net, node, RTC Time, timer, UART and WiFi.

Flash your ESP with it then upload the init file of this project using ESPlorer.

This program uses deepsleep to don't forget to wire GPIO0 and RST to enable it.

## Usage

Update SSID and SSID_PASSWORD according to your WiFi settings and THINGSPEAK_KEY with the API key of ThingSpeak.

When powered, the device will send data to ThingSpeak once every half hour then will sleep.

## Todo

I'm planning to implement end user setup and store information locally when the network is unavailable then put data to ThingSpeak when network goes back.
