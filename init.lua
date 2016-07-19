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
wifi.sta.config (SSID, SSID_PASSWORD, 1)

-- Put the device in deep sleep mode for 30 minutes
local function sleep()
    print("Going to sleep...")
    rtctime.dsleep(1800000000)
end

local function failstorage()
    sleep()
end

-- Simple read adc function
-- Based on voltage divider where R1 = 3.3k and R2 = 1K
-- Needs a Lithium battery (4.3V max)
local function readADC()
    ad = 0
    ad=ad+adc.read(0)*4/978
    print(ad)
    return ad
end

local function readDHT()
  -- Read DHT (all models except DHT11) temperature
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
        print("DHT Checksum error.")
    elseif status == dht.ERROR_TIMEOUT then
        print("DHT timed out.")
    end
end

-- Convert date&time to unix epoch time
local function date2unix(h, n, s, y, m, d, w)
    local a, jd
    a = (14 - m) / 12
    y = y + 4800 - a
    m = m + 12*a - 3
    jd = d + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    return (jd - 2440588)*86400 + h*3600 + n*60 +s
end

-- Hang out until we get a wifi connection.
print("Waiting for connection...")

-- If connection fails, stores data locally then wait 30 minutes.
wifi.sta.eventMonReg(wifi.STA_WRONGPWD, failstorage)
wifi.sta.eventMonReg(wifi.STA_APNOTFOUND, failstorage)
wifi.sta.eventMonReg(wifi.STA_FAIL, failstorage)

-- If connection is successful, read DHT and post
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, function(T)
    print("Config done, IP is " .. T.IP)

    -- If initial boot, then sync RTC to NTP
    -- Only on initial boot to save power
    local _, reset_reason = node.bootreason()
    if reset_reason == 0 or reset_reason == 6 then
      print("Syncing NTP...")
      sntp.sync('85.88.55.5', function(sec,usec,server)
        print('Synced', sec, usec, server)
      end, function(errno)
        print('Sync failed !', errno)
      end)
    end

    readDHT()
end)
