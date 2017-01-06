# TrueSightPulse Solr Plugin
Collects metrics from SOLR using Rest-API from Solr Admin server.

## Prerequisites

### Supported OS

|     OS    | Linux | Windows | SmartOS | OS X |
|:----------|:-----:|:-------:|:-------:|:----:|
| Supported |   v   |         |         |      |

#### Supported Solr Version - Apache Solr 4.5 or later.

#### Boundary Meter Versions V4.5.0-778 or later

- To install new meter go to Settings->Installation or [see instructons|https://help.boundary.com/hc/en-us/sections/200634331-Installation]. 
- To upgrade the meter to the latest version - [see instructons|https://help.boundary.com/hc/en-us/articles/201573102-Upgrading-the-Boundary-Meter].

### Plugin Setup

None

### Plugin Configuration Fields

#### For All Versions

In order for the plugin to collect statistics from SOLR server, it needs access to the cluster stats API endpoint.

|Field Name     |Description                                         |
|:--------------|:---------------------------------------------------|
|host		|SOLR hostname default:localhost		     |
|port           |SOLR Admin port number  default: 8983		     |
|cores		|Solr core(s) that need to be monitored		     |
|sourceName |Source name which will be displayed as source identifier | 
|pollInterval   |How often to query the SOLR service for metrics     |

### Metrics Collected

#### For All Versions

|Metric Name                             |Description                                                                           |
|:---------------------------------------|:-------------------------------------------------------------------------------------|
|SOLR_SYSTEM_COMMITED_VIRTUAL_MEMORY_SIZE|Total commited memory on the system reported by SOLR service                          |
|SOLR_SYSTEM_FREE_PHYSICAL_MEMORY_SIZE   |Amount of free memory on the system reported by SOLR service                          |
|SOLR_SYSTEM_PROCESS_CPU_TIME            |CPU time on the system used by SOLR                                                   |
|SOLR_SYSTEM_OPEN_FILE_DESCRIPTOR_COUNT  |Total amount of file descriptors open in the system                                   |
|SOLR_SYSTEM_MAX_FILE_DESCRIPTOR_COUNT   |Total amount of allowed file descriptors in the system                                |
|SOLR_JVM_UPTIME                         |Number of processors used by SOLR                                                     |
|SOLR_JVM_MEMORY_FREE                    |Amount of free memory in the JVM stack used by SOLR                                   |
|SOLR_JVM_MEMORY_TOTAL                   |The total amount of allocated JVM memory size                                         |
|SOLR_JVM_MEMORY_MAX                     |Total amount of JVM memory used by SOLR since the last startup                        |
|SOLR_JVM_MEMORY_USED                    |Total amount of JVM memory currently in use                                           |
|SOLR_THREAD_CURRENT                     |Number of threads running to serv requests arriving to SOLR                           |
|SOLR_THREAD_PEAK                        |The maximum number of threads in running state since the last startup                 |
|SOLR_THREAD_DAEMON                      |The number of running threads used by the SOLR daemon                                 |
|SOLR_CACHE_DOCUMENT_LOOKUPS             |Total amount of lookups in the document cache                                         |
|SOLR_CACHE_DOCUMENT_HITS                |Total amount of document cache hits (Number of requests where the doc. cache was used)|
|SOLR_CACHE_DOCUMENT_HITRATIO            |The percentage of hits in the document cache                                          |
|SOLR_CACHE_DOCUMENT_INSERTS             |Total amount of inserts in the document cache                                         |
|SOLR_CACHE_DOCUMENT_SIZE                |The size of the document cache                                                        |
|SOLR_CACHE_DOCUMENT_EVICTIONS           |Total amount of evictions in the document cache                                       |
|SOLR_CACHE_DOCUMENT_WARMUPTIME          |The time needed (seconds) to warm up the document cache                               |
