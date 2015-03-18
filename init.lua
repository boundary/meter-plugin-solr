local JSON     = require('json')
local timer    = require('timer')
local http     = require('http')
local https    = require('https')
local boundary = require('boundary')
local io       = require('io')
local _url     = require('_url')
local base64   = require('luvit-base64')


local __pgk        = "BOUNDARY SOLR"
local _previous    = {}
local url          = "http://localhost:8983/solr/"
local core         = nil
local pollInterval = 1000


SYSTEM_ENDPOINT = 'admin/info/system?wt=json'
THREAD_ENDPOINT = 'admin/info/threads?wt=json'
MBEANS_ENDPOINT = 'admin/mbeans?stats=true&wt=json&json.nl=map'


SYSTEM_KEY_MAPPING = {
    {{"mode"}, "SOLR_RUN_MODE", false},
    {{"system", "committedVirtualMemorySize"}, "SOLR_SYSTEM_COMMITED_VIRTUAL_MEMORY_SIZE", false},
    {{"system", "freePhysicalMemorySize"}, "SOLR_SYSTEM_FREE_PHYSICAL_MEMORY_SIZE", false},
    {{"system", "processCpuTime"}, "SOLR_SYSTEM_PROCESS_CPU_TIME", false},
    {{"system", "openFileDescriptorCount"}, "SOLR_SYSTEM_OPEN_FILE_DESCRIPTOR_COUNT", false},
    {{"system", "maxFileDescriptorCount"}, "SOLR_SYSTEM_MAX_FILE_DESCRIPTOR_COUNT", false},
    {{"jvm", "jmx", "upTimeMS"}, "SOLR_JVM_UPTIME", false},
    {{"jvm", "processors"}, "SOLR_JVM_PROCESSORS", false},
    {{"jvm", "memory", "raw", "free"}, "SOLR_JVM_MEMORY_FREE", false},
    {{"jvm", "memory", "raw", "total"}, "SOLR_JVM_MEMORY_TOTAL", false},
    {{"jvm", "memory", "raw", "max"}, "SOLR_JVM_MEMORY_MAX", false},
    {{"jvm", "memory", "raw", "used"}, "SOLR_JVM_MEMORY_USED", false}
}


THREAD_KEY_MAPPING = {
    {{"system", "threadCount", "current"}, "SOLR_THREAD_CURRENT", false},
    {{"system", "threadCount", "peak"}, "SOLR_THREAD_PEAK", false},
    {{"system", "threadCount", "daemon"}, "SOLR_THREAD_DAEMON", false}
}

MBEANS_KEY_MAPPING = {
    {{"solr-mbeans", "CACHE", "documentCache", "stats", "lookups"}, "SOLR_CACHE_DOCUMENT_LOOKUPS", false},
    {{"solr-mbeans", "CACHE", "documentCache", "stats", "hits"}, "SOLR_CACHE_DOCUMENT_HITS", false},
    {{"solr-mbeans", "CACHE", "documentCache", "stats", "hitratio"}, "SOLR_CACHE_DOCUMENT_HITRATIO", false},
    {{"solr-mbeans", "CACHE", "documentCache", "stats", "inserts"}, "SOLR_CACHE_DOCUMENT_INSERTS", false},
    {{"solr-mbeans", "CACHE", "documentCache", "stats", "size"}, "SOLR_CACHE_DOCUMENT_SIZE", false},
    {{"solr-mbeans", "CACHE", "documentCache", "stats", "evictions"}, "SOLR_CACHE_DOCUMENT_EVICTIONS", false},
    {{"solr-mbeans", "CACHE", "documentCache", "stats", "warmupTime"}, "SOLR_CACHE_DOCUMENT_WARMUPTIME", false},
}


if (boundary.param ~= nil) then
  pollInterval = boundary.param.pollInterval or pollInterval
  url          = boundary.param.stats_url or url
  core         = boundary.param.core_name or nil
  source             = (type(boundary.param.source) == 'string' and boundary.param.source:gsub('%s+', '') ~= '' and boundary.param.source) or
   io.popen("uname -n"):read('*line')
  if core then
    MBEANS_ENDPOINT = core .. "/" .. MBEANS_ENDPOINT
  end
end


function berror(err)
  if err then print(string.format("%s ERROR: %s", __pgk, tostring(err))) return err end
end

--- do a http(s) request
local doreq = function(url, cb)
    local u         = _url.parse(url)
    u.protocol      = u.scheme

    for key, val in pairs(u.query) do
      u.path = u.path .. (u.path:find("?") and "&" or "?").. key .. "=" .. val
    end

    local output    = ""
    local onSuccess = function(res)
      res:on("error", function(err)
        cb("Error while receiving a response: " .. tostring(err), nil)
      end)
      res:on("data", function (chunk)
        output = output .. chunk
        if chunk:find("\n") then res:emit("end") end
      end)
      res:on("end", function()
        res:destroy()
        cb(nil, output)
      end)
    end
    local req = (u.scheme == "https") and https.request(u, onSuccess) or http.request(u, onSuccess)
    req:on("error", function(err)
      cb("Error while sending a request: " .. tostring(err), nil)
    end)
    req:done()
end


function diff(a, b)
    if a == nil or b == nil then return 0 end
    return math.max(a - b, 0)
end


-- accumulate a value and return the difference from the previous value
function accumulate(key, newValue)
    local oldValue   = _previous[key] or newValue
    local difference = diff(newValue, oldValue)
    _previous[key]   = newValue
    return difference
end

-- get the natural difference between a and b
function diff(a, b)
  if not a or not b then return 0 end
  return math.max(a - b, 0)
end


function getData(endpoint, mapping)
  local u = url .. endpoint
  doreq(u, function(err, body)
    if berror(err) then return end
    local data = JSON.parse(body)
    for _, val in pairs(mapping) do
      local path  = val[1]
      local name  = val[2]
      local acc   = val[3]
      local value = data
      for i = 1, #path do
        value = value[path[i]]
      end
      if acc then
        value = accumulate(name, value)
      end
      print(string.format('%s %s %s', name, value, source))
    end
  end)
end

print("_bevent:SOLR plugin up : version 1.0|t:info|tags:solr,lua, plugin")

timer.setInterval(pollInterval, function ()
    -- get and print data
    getData(SYSTEM_ENDPOINT, SYSTEM_KEY_MAPPING)
    getData(THREAD_ENDPOINT, THREAD_KEY_MAPPING)
    getData(MBEANS_ENDPOINT, MBEANS_KEY_MAPPING)

end)

