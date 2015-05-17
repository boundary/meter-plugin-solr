local framework            = require('framework')
local url                  = require('url')
local table                = require('table')
local json                 = require('json')
local Plugin               = framework.Plugin
local WebRequestDataSource = framework.WebRequestDataSource
local params               = framework.params
params.pollInterval        = params.pollInterval and tonumber(params.pollInterval)*1000 or 1000
params.name                = 'Boundary Plugin Solr'
params.version             = '2.0'
params.tags                = 'solr'
params.core                = nil


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


SYSTEM_ENDPOINT = '/admin/info/system'
THREAD_ENDPOINT = '/admin/info/threads'
MBEANS_ENDPOINT = '/' .. params.core_name .. '/admin/mbeans'


local options = url.parse(params.url .. SYSTEM_ENDPOINT)
local ds      = WebRequestDataSource:new(options)

ds:chain(function (context, callback, data)
  local data_sources = {}
  for i, v in ipairs({SYSTEM_ENDPOINT, THREAD_ENDPOINT, MBEANS_ENDPOINT}) do
      local options        = url.parse(params.url .. v)
      options.search       = "?stats=true&wt=json&json.nl=map"
      local _ds            = WebRequestDataSource:new(options)
      _ds:propagate('error', context)
      table.insert(data_sources, _ds)
  end
  return data_sources
end)


local plugin = Plugin:new(params, ds)

function plugin:onParseValues(data, extra)
  local result = {}
  local data = json.parse(data)
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
  end
  return result
end

plugin:run()

