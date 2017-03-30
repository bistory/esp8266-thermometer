-- tested on NodeMCU 1.5.1 build 20160626
-- sends temperature and humidity to ThingSpeak
-- https://github.com/bistory/esp8266-thermometer

-- Your Wifi connection data
local SSID = "carotom"
local SSID_PASSWORD = "caranelle"
local THINGSPEAK_CHANNEL = "135257"
local THINGSPEAK_KEY = "4MGIY5OW3TEFJ3QK"
local pin = 4
local logfile = "data.log"
local timeout_tmr = tmr.create()

-- Force ADC mode to external ADC
adc.force_init_mode(adc.INIT_ADC)

-- Configure the ESP as a station (client)
wifi.setmode(wifi.STATION)
wifi.setphymode(wifi.PHYMODE_N)
wifi.sleeptype(wifi.MODEM_SLEEP)
wifi.sta.config(SSID, SSID_PASSWORD, 1)

-- Put the device in deep sleep mode for 30 minutes
local function sleep()
    print("Going to sleep...")
    if m then
        m:close()
    end
    rtctime.dsleep(1800000000, 4)
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

local function trim(s)
    return (s:gsub ("^%s*(.-)%s*$", "%1"))
end

local function writeLog(temp, humi)
    if file.open(logfile, "a+") then
        local time = rtctime.get()
        if time > 0 then
            local tm = rtctime.epoch2cal(time)
            local date = string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", tm["year"], tm["mon"], tm["day"], tm["hour"], tm["min"], tm["sec"])
            file.writeline(date)
            file.writeline(string.format("%.1f", temp))
            file.writeline(string.format("%.1f", humi))
            file.writeline(string.format("%.4f", readADC()))
            file.close()
            print(string.format("Logged data at %s", date))
        end
    end
end

local function readLog()
    print("Reading new line")
    local date = file.readline()
    if (date == nil) then
        file.close()
        print("Removed log file")
        file.remove(logfile)
        sleep()
    end
    local temperature = file.readline()
    local humidity = file.readline()
    local adc = file.readline()

    local route = string.format("channels/%s/publish/%s", THINGSPEAK_CHANNEL, THINGSPEAK_KEY)
    local parameters = string.format("field1=%.1f&field2=%.1f&field3=%.4f&created_at=%s", temperature, humidity, adc, trim(date))
    m:publish(route, parameters, 0, 0, function(client)
            print("Published delayed data")
        end)
end

local function readDHT()
    -- Read DHT (all models except DHT11) temperature
    local status, temp, humi, temp_dec, humi_dec = dht.readxx(pin)

    if wifi.sta.getip() == nil then
        -- Log data when wifi is unavailable
        writeLog(temp, humi)
        sleep()
    else
        if status == dht.OK then
            local route = string.format("channels/%s/publish/%s", THINGSPEAK_CHANNEL, THINGSPEAK_KEY)
            local parameters = string.format("field1=%.1f&field2=%.1f&field3=%.4f", temp, humi, readADC())
            m:publish(route, parameters, 0, 0, function(client)
                print("Published data")
                -- Opens log and send data to the server
                if file.open(logfile, "r") then
                    print("Reading log file...")
    
                    local mytimer = tmr.create()
    
                    mytimer:register(16500, tmr.ALARM_AUTO, function (t)
                        readLog()
                    end)
                    mytimer:start()
                else
                    sleep()
                end
            end)
        elseif status == dht.ERROR_CHECKSUM then
            print("DHT Checksum error.")
            sleep()
        elseif status == dht.ERROR_TIMEOUT then
            print("DHT timed out.")
            sleep()
        end
    end
end

-- Hang out until we get a wifi connection.
print("Waiting for connection...")

-- Force sleep when WiFi is not responding
timeout_tmr:alarm(6000, tmr.ALARM_SINGLE, function()
    if wifi.sta.getip() == nil then
        print('WiFi not responding. Sleeping now.')
        readDHT()
    end
end)

-- If connection fails, stores data locally then wait 30 minutes.
wifi.sta.eventMonReg(wifi.STA_WRONGPWD, failstorage)
wifi.sta.eventMonReg(wifi.STA_APNOTFOUND, failstorage)
wifi.sta.eventMonReg(wifi.STA_FAIL, failstorage)

-- If connection is successful, read DHT and post
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, function(T)
    -- Stops force sleep
    timeout_tmr:unregister()
    print("Config done, IP is " .. T.IP)

    -- Init connection to mqtt server
    m = mqtt.Client("lens_Z0ZfFeZWz2Oe8GJptBAEeTAouNp", 120, "", "")
    m:connect("mqtt.thingspeak.com", 1883, 0, function(client)
        -- If initial boot, then sync RTC to NTP
        -- Only on initial boot to save power
        local sec, _ = rtctime.get()
        if sec == 0 then
            rtcmem.write32(10, 0)
        end
        local mem = rtcmem.read32(10)
    
        if sec == 0 or mem == 0 or mem == 1 then
            print("Syncing NTP...")
            sntp.sync('85.88.55.5', function(sec,usec,server)
                print('Synced', sec, usec, server, mem)
                local memval = 2
                if(mem == 0) then
                    memval = 1
                end
                print(memval)
                rtcmem.write32(10, memval)
                readDHT()
            end, function(errno)
                print('Sync failed !', errno)
                readDHT()
          end)
        else
            -- Force re-sync NTP every 100 calls
            if(mem < 100) then
                mem = mem + 1
                rtcmem.write32(10, mem)
            else
                rtcmem.write32(10, 0)
            end
            readDHT()
        end
    end, function(client, reason)
        readDHT()
    end)
end)
