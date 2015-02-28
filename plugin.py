from __future__ import (absolute_import, division, print_function, unicode_literals)
import logging
import datetime
import time
import sys
import urllib2
import urlparse
import json

import boundary_plugin
import boundary_accumulator

"""
If getting statistics fails, we will retry up to this number of times before
giving up and aborting the plugin.  Use 0 for unlimited retries.
"""
PLUGIN_RETRY_COUNT = 0
"""
If getting statistics fails, we will wait this long (in seconds) before retrying.
"""
PLUGIN_RETRY_DELAY = 5
"""
We have multiple endpoints for retriving the different status
"""
SYSTEM_ENDPOINT='admin/info/system?wt=json'
THREAD_ENDPOINT='admin/info/threads?wt=json'
MBEANS_ENDPOINT='admin/mbeans?stats=true&wt=json&json.nl=map'

SYSTEM_KEY_MAPPING = (
    (["mode"], "SOLR_RUN_MODE", False),
    (["system", "committedVirtualMemorySize"], "SOLR_SYSTEM_COMMITED_VIRTUAL_MEMORY_SIZE", False),
    (["system", "freePhysicalMemorySize"], "SOLR_SYSTEM_FREE_PHYSICAL_MEMORY_SIZE", False),
    (["system", "processCpuTime"], "SOLR_SYSTEM_PROCESS_CPU_TIME", False),
    (["system", "openFileDescriptorCount"], "SOLR_SYSTEM_OPEN_FILE_DESCRIPTOR_COUNT", False),
    (["system", "maxFileDescriptorCount"], "SOLR_SYSTEM_MAX_FILE_DESCRIPTOR_COUNT", False), 
    (["jvm", "jmx", "upTimeMS"], "SOLR_JVM_UPTIME", False),
    (["jvm", "processors"], "SOLR_JVM_PROCESSORS", False),
    (["jvm", "memory", "raw", "free"], "SOLR_JVM_MEMORY_FREE", False),
    (["jvm", "memory", "raw", "total"], "SOLR_JVM_MEMORY_TOTAL", False),
    (["jvm", "memory", "raw", "max"], "SOLR_JVM_MEMORY_MAX", False),
    (["jvm", "memory", "raw", "used"], "SOLR_JVM_MEMORY_USED", False)
)


THREAD_KEY_MAPPING = (
    (["system", "threadCount", "current"], "SOLR_THREAD_CURRENT", False),
    (["system", "threadCount", "peak"], "SOLR_THREAD_PEAK", False),
    (["system", "threadCount", "daemon"], "SOLR_THREAD_DAEMON", False)
)

MBEANS_KEY_MAPPING = (
    (["solr-mbeans", "CACHE", "documentCache", "stats", "lookups"], "SOLR_CACHE_DOCUMENT_LOOKUPS", False),
    (["solr-mbeans", "CACHE", "documentCache", "stats", "hits"], "SOLR_CACHE_DOCUMENT_HITS", False),
    (["solr-mbeans", "CACHE", "documentCache", "stats", "hitratio"], "SOLR_CACHE_DOCUMENT_HITRATIO", False),
    (["solr-mbeans", "CACHE", "documentCache", "stats", "inserts"], "SOLR_CACHE_DOCUMENT_INSERTS", False),
    (["solr-mbeans", "CACHE", "documentCache", "stats", "size"], "SOLR_CACHE_DOCUMENT_SIZE", False),
    (["solr-mbeans", "CACHE", "documentCache", "stats", "evictions"], "SOLR_CACHE_DOCUMENT_EVICTIONS", False),
    (["solr-mbeans", "CACHE", "documentCache", "stats", "warmupTime"], "SOLR_CACHE_DOCUMENT_WARMUPTIME", False),
)

class SolrPlugin(object):
    def __init__(self, boundary_metric_prefix):
        self.boundary_metric_prefix = boundary_metric_prefix
        self.settings = boundary_plugin.parse_params()
        self.accumulator = boundary_accumulator
	self.base_url = self.settings.get("base_url", "http://localhost:8983/solr/")

    def get_stats(self):
	mbeans_endpoint_with_core = MBEANS_ENDPOINT
	system = self.get_raw_data(SYSTEM_ENDPOINT)
	threads = self.get_raw_data(THREAD_ENDPOINT)
	
	if self.core:
	  mbeans_endpoint_with_core = self.core + '/' + MBEANS_ENDPOINT
	mbeans = self.get_raw_data(mbeans_endpoint_with_core)
	
	return {'system': system, 'threads': threads, 'mbeans': mbeans}

    def get_raw_data(self, endpoint):
	req = urllib2.urlopen(urlparse.urljoin(self.base_url, endpoint))
        res = req.read()
        req.close()

        data = json.loads(res)
        return data

    def get_stats_with_retries(self, *args, **kwargs):
        """
        Calls the get_stats function, taking into account retry configuration.
        """
        retry_range = xrange(PLUGIN_RETRY_COUNT) if PLUGIN_RETRY_COUNT > 0 else iter(int, 1)
        for _ in retry_range:
            try:
                return self.get_stats(*args, **kwargs)
            except Exception as e:
                logging.error("Error retrieving data: %s" % e)
                time.sleep(PLUGIN_RETRY_DELAY)

        logging.fatal("Max retries exceeded retrieving data")
        raise Exception("Max retries exceeded retrieving data")

    def handle_metric_for_system(self, data):
	for metric_path, boundary_name, accumulate in SYSTEM_KEY_MAPPING:
	    value = data
            try:
                for p in metric_path:
                    value = value[p]
            except KeyError:
                value = None

	    if not value:
                continue

	    if accumulate:
                value = self.accumulator.accumulate(metric_path, value)

	    boundary_plugin.boundary_report_metric(self.boundary_metric_prefix + boundary_name, value)

    def handle_metric_for_threads(self, data):
        for metric_path, boundary_name, accumulate in THREAD_KEY_MAPPING:
            value = data
            try:
                for p in metric_path:
                    value = value[p]
            except KeyError:
                value = None

            if not value:
                continue

            if accumulate:
                value = self.accumulator.accumulate(metric_path, value)

            boundary_plugin.boundary_report_metric(self.boundary_metric_prefix + boundary_name, value)

    def handle_metric_for_caches(self, data):
        for metric_path, boundary_name, accumulate in MBEANS_KEY_MAPPING:
            value = data
            try:
                for p in metric_path:
                    value = value[p]
            except KeyError:
                value = None

            if not value:
                continue

            if accumulate:
                value = self.accumulator.accumulate(metric_path, value)

            boundary_plugin.boundary_report_metric(self.boundary_metric_prefix + boundary_name, value)

    def handle_metrics(self, data):
	self.handle_metric_for_system(data['system'])
	self.handle_metric_for_threads(data['threads'])
	self.handle_metric_for_caches(data['mbeans'])

    def main(self):
        logging.basicConfig(level=logging.ERROR, filename=self.settings.get('log_file', None))
        reports_log = self.settings.get('report_log_file', None)
        if reports_log:
            boundary_plugin.log_metrics_to_file(reports_log)

	self.core = self.settings.get('core_name', None)

        boundary_plugin.start_keepalive_subprocess()

        while True:
            data = self.get_stats_with_retries()
            self.handle_metrics(data)
            boundary_plugin.sleep_interval()


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '-v':
        logging.basicConfig(level=logging.INFO)

    plugin = SolrPlugin('')
    plugin.main()
