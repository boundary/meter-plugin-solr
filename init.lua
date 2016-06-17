-- Copyright 2015 BMC Software, Inc.
-- --
-- -- Licensed under the Apache License, Version 2.0 (the "License");
-- -- you may not use this file except in compliance with the License.
-- -- You may obtain a copy of the License at
-- --
-- --    http://www.apache.org/licenses/LICENSE-2.0
-- --
-- -- Unless required by applicable law or agreed to in writing, software
-- -- distributed under the License is distributed on an "AS IS" BASIS,
-- -- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- -- See the License for the specific language governing permissions and
-- -- limitations under the License.

--Framework imports.
local framework = require('framework')

local Plugin = framework.Plugin
local WebRequestDataSource = framework.WebRequestDataSource
local DataSourcePoller = framework.DataSourcePoller
local PollerCollection = framework.PollerCollection
local isHttpSuccess = framework.util.isHttpSuccess
local ipack = framework.util.ipack
local parseJson = framework.util.parseJson

--Getting the parameters from params.json.
local params = framework.params

local SYSTEM_KEY = 'system_details_key'
local THREAD_KEY = 'thread_details_key'
local MBEAN_KEY = 'mbean_details_key'

local function createOptions(item)

	local options = {}
	options.host = item.host
	options.port = item.port
	options.wait_for_end = false

	return options
end

local function createSystemDataSource(item)

        local options = createOptions(item)

	options.path = "/solr/admin/info/system?wt=json"
	options.meta = {SYSTEM_KEY, item}

        return WebRequestDataSource:new(options)
end

local function createThreadDataSource(item)

	local options = createOptions(item)

	options.path = "/solr/admin/info/threads?wt=json"
	options.meta = {THREAD_KEY, item}

	return WebRequestDataSource:new(options)
end

local function createMbeanDataSource(item)
	local options = createOptions(item)

        options.path = ("/solr/%s/admin/mbeans?stats=true&wt=json&json.nl=map"):format(item.core)
	options.meta = {MBEAN_KEY, item}

        return WebRequestDataSource:new(options)
end

local function createPollers(params)
	local pollers = PollerCollection:new()

	for _, item in pairs(params.items) do
		local tds = createThreadDataSource(item)
		local threadPoller = DataSourcePoller:new(5000, tds)
		pollers:add(threadPoller)

		local sds = createSystemDataSource(item)
		local systemPoller = DataSourcePoller:new(item.pollInterval, sds)
		pollers:add(systemPoller)

		local mds = createMbeanDataSource(item)
		local mbeanPoller = DataSourcePoller:new(item.pollInterval, mds)
	        pollers:add(mbeanPoller)
	end

	return pollers
end

local function systemDetailsExtractor (data, item)
	local result = {}
	local metric = function (...) ipack(result, ...) end

	metric('SOLR_SYSTEM_COMMITED_VIRTUAL_MEMORY_SIZE', data.system.committedVirtualMemorySize, nil, item.core)
	metric('SOLR_SYSTEM_FREE_PHYSICAL_MEMORY_SIZE', data.system.freePhysicalMemorySize, nil, item.core)
	metric('SOLR_SYSTEM_PROCESS_CPU_TIME', data.system.processCpuTime, nil, item.core)
	metric('SOLR_SYSTEM_OPEN_FILE_DESCRIPTOR_COUNT', data.system.openFileDescriptorCount, nil, item.core)
	metric('SOLR_SYSTEM_MAX_FILE_DESCRIPTOR_COUNT', data.system.maxFileDescriptorCount, nil, item.core)
	metric('SOLR_JVM_UPTIME', data.jvm.jmx.upTimeMS, nil, item.core)
	metric('SOLR_JVM_PROCESSORS', data.jvm.processors, nil, item.core)
	metric('SOLR_JVM_MEMORY_FREE', data.jvm.memory.raw.free, nil, item.core)
	metric('SOLR_JVM_MEMORY_TOTAL', data.jvm.memory.raw.total, nil, item.core)
	metric('SOLR_JVM_MEMORY_MAX', data.jvm.memory.raw.max, nil, item.core)
	metric('SOLR_JVM_MEMORY_USED', data.jvm.memory.raw.used, nil, item.core)

	return result
end

local function threadDetailsExtractor (data, item)
        local result = {}
        local metric = function (...) ipack(result, ...) end

        metric('SOLR_THREAD_CURRENT', data.system.threadCount.current, nil, item.core)
	metric('SOLR_THREAD_PEAK', data.system.threadCount.peak, nil, item.core)
	metric('SOLR_THREAD_DAEMON', data.system.threadCount.daemon, nil, item.core)

        return result
end

local function mbeanDetailsExtractor (data, item)
        local result = {}
        local metric = function (...) ipack(result, ...) end

	--Direct reference like data.solr-mbeans.CACHE... fails due to '-' in the string.
	local solrMbeans = data['solr-mbeans']

        metric('SOLR_CACHE_DOCUMENT_LOOKUPS', solrMbeans.CACHE.documentCache.stats.lookups, nil, item.core)
	metric('SOLR_CACHE_DOCUMENT_HITS', solrMbeans.CACHE.documentCache.stats.hits, nil, item.core)
	metric('SOLR_CACHE_DOCUMENT_HITRATIO', solrMbeans.CACHE.documentCache.stats.hitratio, nil, item.core)
	metric('SOLR_CACHE_DOCUMENT_INSERTS', solrMbeans.CACHE.documentCache.stats.inserts, nil, item.core)
	metric('SOLR_CACHE_DOCUMENT_SIZE', solrMbeans.CACHE.documentCache.stats.size, nil, item.core)
	metric('SOLR_CACHE_DOCUMENT_EVICTIONS', solrMbeans.CACHE.documentCache.stats.evictions, nil, item.core)
	metric('SOLR_CACHE_DOCUMENT_WARMUPTIME',  solrMbeans.CACHE.documentCache.stats.warmupTime, nil, item.core)

        return result
end

local extractors_map = {}
extractors_map[SYSTEM_KEY] = systemDetailsExtractor
extractors_map[THREAD_KEY] = threadDetailsExtractor
extractors_map[MBEAN_KEY] = mbeanDetailsExtractor


local pollers = createPollers(params)
local plugin = Plugin:new(params, pollers)

--Response returned for each of the pollers.
function plugin:onParseValues(data, extra)
	local success, parsed = parseJson(data)

	if not isHttpSuccess(extra.status_code) then
		self:emitEvent('error', ('Http request returned status code %s instead of OK. Please verify configuration.'):format(extra.status_code))
    		return
	end

	local success, parsed = parseJson(data)
  	if not success then
		self:emitEvent('error', 'Cannot parse metrics. Please verify configuration.') 
		return
	end

	local key, item = unpack(extra.info)
	local extractor = extractors_map[key]
	return extractor(parsed, item)

end

plugin:run()


