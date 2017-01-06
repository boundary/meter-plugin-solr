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
local notEmpty = framework.string.notEmpty
local clone = framework.table.clone

--Getting the parameters from params.json.
local params = framework.params

--These constants will be used to differentiate between callbacks.
local SYSTEM_KEY = 'system_details_key'
local THREAD_KEY = 'thread_details_key'
local MBEAN_KEY = 'mbean_details_key'

--Create the base options object.
local function createOptions(item)
	local options = {}
	options.host = item.host
	options.port = item.port
	options.wait_for_end = true
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

local function createMbeanDataSource(item, coreName)
	local options = createOptions(item)
        options.path = ("/solr/%s/admin/mbeans?stats=true&wt=json&json.nl=map"):format(coreName)
	item.coreName = coreName
	options.meta = {MBEAN_KEY, item}
        return WebRequestDataSource:new(options)
end

--Function creates all the pollers required for the plugin.
--Multiple MbeanDataSources will be created for each of the cores specified.
local function createPollers(params)
	local pollers = PollerCollection:new()

	for _, item in pairs(params.items) do
		local tds = createThreadDataSource(item)
		local threadPoller = DataSourcePoller:new(item.pollInterval, tds)
		pollers:add(threadPoller)

		local sds = createSystemDataSource(item)
		local systemPoller = DataSourcePoller:new(item.pollInterval, sds)
		pollers:add(systemPoller)

		for i, v in ipairs(item.cores) do
			if notEmpty(v) then
				--item table will be cloned to avoid getting overwritten in multicore scenarios.
				local myitem = clone(item)
				local mds = createMbeanDataSource(myitem, v)
				local mbeanPoller = DataSourcePoller:new(myitem.pollInterval, mds)
				pollers:add(mbeanPoller)
			end
		end
	end

	return pollers
end

local function systemDetailsExtractor (data, item)
	local result = {}
	local metric = function (...) ipack(result, ...) end

	local source = item.sourceName
	metric('SOLR_SYSTEM_COMMITED_VIRTUAL_MEMORY_SIZE', data.system.committedVirtualMemorySize, nil, source)
	metric('SOLR_SYSTEM_FREE_PHYSICAL_MEMORY_SIZE', data.system.freePhysicalMemorySize, nil, source)
	metric('SOLR_SYSTEM_PROCESS_CPU_TIME', data.system.processCpuTime, nil, source)
	metric('SOLR_SYSTEM_OPEN_FILE_DESCRIPTOR_COUNT', data.system.openFileDescriptorCount, nil, source)
	metric('SOLR_SYSTEM_MAX_FILE_DESCRIPTOR_COUNT', data.system.maxFileDescriptorCount, nil, source)
	metric('SOLR_JVM_UPTIME', data.jvm.jmx.upTimeMS, nil, source)
	metric('SOLR_JVM_MEMORY_FREE', data.jvm.memory.raw.free, nil, source)
	metric('SOLR_JVM_MEMORY_TOTAL', data.jvm.memory.raw.total, nil, source)
	metric('SOLR_JVM_MEMORY_MAX', data.jvm.memory.raw.max, nil, source)
	metric('SOLR_JVM_MEMORY_USED', data.jvm.memory.raw.used, nil, source)

	return result
end

local function threadDetailsExtractor (data, item)
        local result = {}
        local metric = function (...) ipack(result, ...) end
	
	local source = item.sourceName
        metric('SOLR_THREAD_CURRENT', data.system.threadCount.current, nil, source)
	metric('SOLR_THREAD_PEAK', data.system.threadCount.peak, nil, source)
	metric('SOLR_THREAD_DAEMON', data.system.threadCount.daemon, nil, source)

        return result
end

local function mbeanDetailsExtractor (data, item)
        local result = {}
        local metric = function (...) ipack(result, ...) end

	--Direct reference like data.solr-mbeans.CACHE... fails due to '-' in the string.
	local solrMbeans = data['solr-mbeans']

	local source = item.sourceName .. "-" .. item.coreName
        metric('SOLR_CACHE_DOCUMENT_LOOKUPS', solrMbeans.CACHE.documentCache.stats.lookups, nil, source)
	metric('SOLR_CACHE_DOCUMENT_HITS', solrMbeans.CACHE.documentCache.stats.hits, nil, source)
	metric('SOLR_CACHE_DOCUMENT_HITRATIO', solrMbeans.CACHE.documentCache.stats.hitratio, nil, source)
	metric('SOLR_CACHE_DOCUMENT_INSERTS', solrMbeans.CACHE.documentCache.stats.inserts, nil, source)
	metric('SOLR_CACHE_DOCUMENT_SIZE', solrMbeans.CACHE.documentCache.stats.size, nil, source)
	metric('SOLR_CACHE_DOCUMENT_EVICTIONS', solrMbeans.CACHE.documentCache.stats.evictions, nil, source)
	metric('SOLR_CACHE_DOCUMENT_WARMUPTIME',  solrMbeans.CACHE.documentCache.stats.warmupTime, nil, source)

        return result
end

local extractors_map = {}
extractors_map[SYSTEM_KEY] = systemDetailsExtractor
extractors_map[THREAD_KEY] = threadDetailsExtractor
extractors_map[MBEAN_KEY] = mbeanDetailsExtractor

local pollers = createPollers(params)

--Plugin is created with the created pollers. Each of the poller will reponse with the callback funtion plugin:onParseValues()
local plugin = Plugin:new(params, pollers)

--Callback for each of the pollers.
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

	--extractor_map is used to identify the extractor for the corresponding callback.
	local key, item = unpack(extra.info)
	local extractor = extractors_map[key]

	--Calling the extractor function.
	return extractor(parsed, item)

end

plugin:run()


