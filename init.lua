-- tested on NodeMCU 2.1.0 build 20170527
-- sends temperature and humidity to ThingSpeak
-- https://github.com/bistory/esp8266-thermometer

-- Your Wifi connection data
local SSID = "xxxxx"
local SSID_PASSWORD = "xxxxx"
local THINGSPEAK_CHANNEL = "xxxxx"
local THINGSPEAK_KEY = "xxxxx"
local SDA_PIN = 6 -- sda pin, GPIO12
local SCL_PIN = 5 -- scl pin, GPIO14
local logfile = "data.log"
--local m = nil
local temp = 0
local humi = 0
local timeout_tmr = tmr.create()

-- Force ADC mode to external ADC
adc.force_init_mode(adc.INIT_ADC)

-- Configure the ESP as a station (client)
wifi.setmode(wifi.STATION)
wifi.setphymode(wifi.PHYMODE_N)
station_cfg={}
station_cfg.ssid = SSID
station_cfg.pwd = SSID_PASSWORD
station_cfg.auto = true
wifi.sta.config(station_cfg)

-- Put the device in deep sleep mode for 30 minutes
local function sleep()
    local log = rtcmem.read32(11)
    if(log > 0) then
        print("Going to sleep 15s...")
        -- Wait 15 seconds to reboot device
        -- if he is reading log
        rtctime.dsleep(15000000)
    else
        print("Going to sleep 30min...")
        rtctime.dsleep(1800000000)
        --rtctime.dsleep(18000000)
    end
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
    print("ADC", ad)
    return ad
end

local function trim(s)
    return (s:gsub ("^%s*(.-)%s*$", "%1"))
end

local function writeLog(temp, humi)
    local log = file.open(logfile, "a+")
    if log then
        local time = rtctime.get()
        if time > 0 then
            local tm = rtctime.epoch2cal(time)
            local date = string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", tm["year"], tm["mon"], tm["day"], tm["hour"], tm["min"], tm["sec"])
            log:writeline(date)
            log:writeline(string.format("%.1f", temp))
            log:writeline(string.format("%.1f", humi))
            log:writeline(string.format("%.4f", readADC()))
            log:close()
            print(string.format("Logged data at %s", date))
        end
    end
end

local function readLog()
    local log = file.open(logfile, "r")
    local date = nil
    local temperature = nil
    local humidity = nil
    local adc = nil

    local logline = rtcmem.read32(11)
    for i=1,logline,4 do
       print("Reading new line")
       date = log:readline()
       temperature = log:readline()
       humidity = log:readline()
       adc = log:readline()
    end
    
    if (date == nil) then
        log:close()
        print("Removed log file")
        file.remove(logfile)
        rtcmem.write32(11, 0)
        sleep()
    else
        local trim_adc = trim(adc)
        local trim_date = trim(date)

        local route = string.format("http://api.thingspeak.com/update?api_key=%s&field1=%.1f&field2=%.1f&field3=%.4f&created_at=%s", THINGSPEAK_KEY, temp, humi, trim_adc, trim_date)
        http.get(route, nil, function(code, data)
          if (code < 0) then
            print("HTTP request failed")
            sleep()
          else
            rtcmem.write32(11, logline + 1)
            print("Published delayed data", string.format("%.1f°C %.1f adc: %.4f", temp, humi, trim_adc))
            sleep()
          end
        end)
    end
end

local function sendData()
    if wifi.sta.getip() == nil then
        -- Log data when wifi is unavailable
        writeLog(temp, humi)
        sleep()
    else
        local adc_data = readADC()
        local route = string.format("http://api.thingspeak.com/update?api_key=%s&field1=%.1f&field2=%.1f&field3=%.4f", THINGSPEAK_KEY, temp, humi, adc_data)
        http.get(route, nil, function(code, data)
          if (code < 0) then
            print("HTTP request failed")
            writeLog(temp, humi)
            sleep()
          else
            print("Published data", string.format("%.1f°C %.1f adc: %.4f", temp, humi, adc_data))

            -- Check if there is a log
            if(file.exists(logfile)) then
                rtcmem.write32(11, 1)
                print("Found a log !")
            end
            sleep()
          end
        end)
    end
end

function mqttConnection()
    local log = rtcmem.read32(11)
    if(log > 0) then
        print("Reading log")
        readLog()
    else
        print("Sending data")
        sendData()
    end
end

-- Hang out until we get a wifi connection.
print("Waiting for connection...")

-- Force sleep when WiFi is not responding
timeout_tmr:alarm(6000, tmr.ALARM_SINGLE, function()
    if wifi.sta.getip() == nil then
        print('WiFi not responding. Sleeping now.')
        sendData()
    end
end)

-- Read si7021 temperature and humidity while waiting for connection
i2c.setup(0, SDA_PIN, SCL_PIN, i2c.SLOW)
si7021.setup()
humi, temp, humi_dec, temp_dec = si7021.read()

-- If connection fails, stores data locally then wait 30 minutes
--wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, failstorage)

-- If connection is successful, post data
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, function(T)
    -- Stops force sleep
    timeout_tmr:unregister()
    print("Config done, IP is " .. T.IP)

    -- If initial boot, then sync RTC to NTP
    -- Only on initial boot to save power
    local sec, _ = rtctime.get()
    print('rtc', rtcmem.read32(10))
    print('logmem', rtcmem.read32(11))
    if sec == 0 then
        rtcmem.write32(10, 0)
        rtcmem.write32(11, 0)
    end
    local mem = rtcmem.read32(10)

    if sec == 0 or mem == 0 then
        print("Syncing NTP...")
        sntp.sync(nil, function(sec,usec,server)
            print("Synced", sec, usec, server, mem)
            local memval = 2
            if(mem == 0) then
                memval = 1
            end
            print("Memval", memval)
            rtcmem.write32(10, memval)
            mqttConnection()
        end, function(errno)
            print("Sync failed !", errno)
            mqttConnection()
      end)
    else
        -- Force re-sync NTP every 100 calls
        if(mem < 100) then
            mem = mem + 1
            rtcmem.write32(10, mem)
        else
            rtcmem.write32(10, 0)
        end
        mqttConnection()
    end
end)
