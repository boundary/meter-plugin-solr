Boundary SOLR Plugin
-----------------------------
Collects metrics from SOLR server.

### Platforms
- Linux

### Prerequisites
- Python 2.6 or later
- SOLR 4+

### Plugin Configuration

In order for the plugin to collect statistics from SOLR server, it needs access to the cluster stats API endpoint.
In a default installation, this would be "http://localhost:8983/solr/", but the port or path may be
modified in configuration. 
Changing the base_url setting in params.json allow the plugin to collect the metrics from remote hosts.

Using the optional parameter core_name, it is possible to set the core from where the metrics are fetched. 
If no core_name is specified, the system default will be used.
