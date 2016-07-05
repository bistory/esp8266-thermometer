-- tested on NodeMCU 1.5.1 build 20160626
-- sends temperature and humidity to ThingSpeak
-- https://github.com/bistory/esp8266-thermometer

-- Your Wifi connection data
local SSID = "xxxxx"
local SSID_PASSWORD = "xxxxx"
local THINGSPEAK_KEY = "xxxxx"
local pin = 4

-- Configure the ESP as a station (client)
wifi.setmode (wifi.STATION)
wifi.sta.config (SSID, SSID_PASSWORD)
wifi.sta.autoconnect (1)

-- Simple read adc function
-- Based on voltage divider where R1 = 3.3k and R2 = 1K
-- Needs a Lithium battery (4.3V max)
function readADC()
    ad = 0
    ad=ad+adc.read(0)*4/9.78
    print(ad)
    return ad
end

function sleep()
    node.dsleep(1800000000)
end

-- Hang out until we get a wifi connection before the httpd server is started.
print ("Waiting for connection...")
wifi.sta.eventMonReg(wifi.STA_WRONGPWD, sleep)
wifi.sta.eventMonReg(wifi.STA_APNOTFOUND, sleep)
wifi.sta.eventMonReg(wifi.STA_FAIL, sleep)
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, function(T)
    print ("Config done, IP is " .. T.IP)
    local status, temp, humi, temp_dec, humi_dec = dht.readxx(pin)

    if status == dht.OK then
        http.get(string.format("https://api.thingspeak.com/update?api_key=%s&field1=%d.%03d&field2=%d.%03d&field3=%d",
          THINGSPEAK_KEY,
          math.floor(temp),
          temp_dec,
          math.floor(humi),
          humi_dec,
          readADC()), nil, function(code, data)
            if (code < 0) then
                print("HTTP request failed")
            else
                print(code, data)
            end
            sleep()
        end)
    elseif status == dht.ERROR_CHECKSUM then
        print( "DHT Checksum error." )
    elseif status == dht.ERROR_TIMEOUT then
        print( "DHT timed out." )
    end
end)
