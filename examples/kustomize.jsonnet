local k = import 'ksonnet/ksonnet.beta.4/k.libsonnet';
local kp =
  (import 'kube-prometheus/kube-prometheus.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-static-etcd.libsonnet') +
//(import 'kube-prometheus/ksm-autoscaler/ksm-autoscaler.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-strip-limits.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-anti-affinity.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-node-affinity.libsonnet')
  {
    _config+:: {
      namespace: 'kubesphere-monitoring-system',

      versions+:: {
        prometheus: "v2.11.0",
        alertmanager: "v0.18.0",
        kubeStateMetrics: "v1.8.0",
        kubeRbacProxy: "v0.4.1",
        addonResizer: "1.8.4",
        nodeExporter: "ks-v0.18.1", 
        prometheusOperator: 'v0.33.0',
        configmapReloader: 'v0.0.1',
        prometheusConfigReloader: 'v0.33.0',
        prometheusAdapter: 'v0.4.1',
        thanos: "v0.7.0",
        clusterVerticalAutoscaler: "1.0.0"
      },

      imageRepos+:: {
        prometheus: "kubesphere/prometheus",
        alertmanager: "kubesphere/alertmanager",
        kubeStateMetrics: "kubesphere/kube-state-metrics",
        kubeRbacProxy: "kubesphere/kube-rbac-proxy",
        addonResizer: "kubesphere/addon-resizer",
        nodeExporter: "kubesphere/node-exporter",
        prometheusOperator: "kubesphere/prometheus-operator",
        configmapReloader: 'kubesphere/configmap-reload',
        prometheusConfigReloader: 'kubesphere/prometheus-config-reloader',
        prometheusAdapter: 'kubesphere/k8s-prometheus-adapter-amd64',
        thanos: 'kubesphere/thanos',
        clusterVerticalAutoscaler: 'gcr.io/google_containers/cluster-proportional-vertical-autoscaler-amd64'
      },

      prometheus+:: {
        namePrefix: 'ks-',
        retention: '7d',
        scrapeInterval: '1m',
        namespaces: ['default', 'kube-system', 'kubesphere-devops-system', 'istio-system', $._config.namespace],
        serviceMonitorSelector: {},
        storage: {
          volumeClaimTemplate: {
            spec: {
              resources: {
                requests: {
                  storage: '20Gi',
                },
              },
            },
          },
        },
        query: {
          maxConcurrency: 1000 
        },
        tolerations: [
          {
            key: 'dedicated',
            operator: 'Equal',
            value: 'monitoring',
            effect: 'NoSchedule',
          },
        ],
      },

      alertmanager+:: {
        config+: {
          route+: {
            group_by: ['alertname', 'namespace'],
          },
        },
      },

      kubeStateMetrics+:: {
        name: 'ks-kube-state-metrics',
        scrapeInterval: '1m',
      },

      nodeExporter+:: {
        name: 'ks-node-exporter',
      },

      prometheusOperator+:: {
        name: 'ks-prometheus-operator',
      },
      etcd+:: {
        ips: ['127.0.0.1'],
        clientCA: importstr 'etcd-client-ca.crt',
        clientKey: importstr 'etcd-client.key',
        clientCert: importstr 'etcd-client.crt',
        serverName: 'etcd.kube-system.svc.cluster.local',
      },
      prometheusAdapter+:: {
        namePrefix: 'ks-',
        customMetricsClusterRole: 'custom-metrics-server-resources',
        hpaCustomMetricsClusterRole: 'hpa-controller-custom-metrics',
        hpaServiceAccount: 'horizontal-pod-autoscaler',
        hpaNameSpace: 'kube-system',
        config: |||
          rules:
          - seriesQuery: '{namespace!="",__name__!~"^container_.*"}'
            seriesFilters:
            - isNot: .*_total$
            resources:
              template: <<.Resource>>
            name:
              matches: ""
              as: ""
            metricsQuery: sum(<<.Series>>{<<.LabelMatchers>>}) by (<<.GroupBy>>)
          - seriesQuery: '{namespace!="",__name__!~"^container_.*"}'
            seriesFilters:
            - isNot: .*_seconds_total
            resources:
              template: <<.Resource>>
            name:
              matches: ^(.*)_total$
              as: ""
            metricsQuery: sum(rate(<<.Series>>{<<.LabelMatchers>>}[2m])) by (<<.GroupBy>>)
          - seriesQuery: '{namespace!="",__name__!~"^container_.*"}'
            seriesFilters: []
            resources:
              template: <<.Resource>>
            name:
              matches: ^(.*)_seconds_total$
              as: ""
            metricsQuery: sum(rate(<<.Series>>{<<.LabelMatchers>>}[2m])) by (<<.GroupBy>>)
          resourceRules:
            cpu:
              containerQuery: sum(irate(container_cpu_usage_seconds_total{<<.LabelMatchers>>,container!="POD",container!="",pod!=""}[5m])) by (<<.GroupBy>>)
              nodeQuery: sum(irate(node_cpu_seconds_total{mode="used"}[5m]) * on(namespace, pod) group_left(node) node_namespace_pod:kube_pod_info:{<<.LabelMatchers>>}) by (<<.GroupBy>>)
              resources:
                overrides:
                  node:
                    resource: node
                  namespace:
                    resource: namespace
                  pod:
                    resource: pod
              containerLabel: container
            memory:
              containerQuery: sum(container_memory_working_set_bytes{<<.LabelMatchers>>,container!="POD",container!="",pod!=""}) by (<<.GroupBy>>)
              nodeQuery: sum(node_memory_MemTotal_bytes{job="node-exporter",<<.LabelMatchers>>} - node_memory_MemFree_bytes{job="node-exporter",<<.LabelMatchers>>} - node_memory_Cached_bytes{job="node-exporter",<<.LabelMatchers>>} - node_memory_Buffers_bytes{job="node-exporter",<<.LabelMatchers>>} - node_memory_SReclaimable_bytes{job="node-exporter",<<.LabelMatchers>>}) by (<<.GroupBy>>)
              resources:
                overrides:
                  instance:
                    resource: node
                  namespace:
                    resource: namespace
                  pod:
                    resource: pod
              containerLabel: container
            window: 5m
        |||,
      },
    },

    alertmanager+:: {
      serviceMonitor+:
        {
          spec+: {
            endpoints: [
              {
                port: 'web',
                interval: '1m',
              },
            ],
          },
        },      
    }, 

    grafana+:: {
      serviceMonitor+:
        {
          spec+: {
            endpoints: [
              {
                port: 'http',
                interval: '1m',
              },
            ],
          },
        },      
    }, 
    kubeStateMetrics+:: {
      clusterRoleBinding:
        local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
  
        clusterRoleBinding.new() +
        clusterRoleBinding.mixin.metadata.withName($._config.kubeStateMetrics.name) +
        clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
        clusterRoleBinding.mixin.roleRef.withName('kube-state-metrics') +
        clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
        clusterRoleBinding.withSubjects([{ kind: 'ServiceAccount', name: 'kube-state-metrics', namespace: $._config.namespace }]),
      deployment:
        local deployment = k.apps.v1.deployment;
        local container = deployment.mixin.spec.template.spec.containersType;
        local volume = deployment.mixin.spec.template.spec.volumesType;
        local containerPort = container.portsType;
        local containerVolumeMount = container.volumeMountsType;
        local podSelector = deployment.mixin.spec.template.spec.selectorType;
  
        local podLabels = { app: 'kube-state-metrics' };
  
        local proxyClusterMetrics =
          container.new('kube-rbac-proxy-main', $._config.imageRepos.kubeRbacProxy + ':' + $._config.versions.kubeRbacProxy) +
          container.withArgs([
            '--logtostderr',
            '--secure-listen-address=:8443',
            '--tls-cipher-suites=' + std.join(',', $._config.tlsCipherSuites),
            '--upstream=http://127.0.0.1:8081/',
          ]) +
          container.withPorts(containerPort.newNamed(8443, 'https-main',)) +
          container.mixin.resources.withRequests($._config.resources['kube-rbac-proxy'].requests) +
          container.mixin.resources.withLimits($._config.resources['kube-rbac-proxy'].limits);
  
        local proxySelfMetrics =
          container.new('kube-rbac-proxy-self', $._config.imageRepos.kubeRbacProxy + ':' + $._config.versions.kubeRbacProxy) +
          container.withArgs([
            '--logtostderr',
            '--secure-listen-address=:9443',
            '--tls-cipher-suites=' + std.join(',', $._config.tlsCipherSuites),
            '--upstream=http://127.0.0.1:8082/',
          ]) +
          container.withPorts(containerPort.newNamed(9443, 'https-self',)) +
          container.mixin.resources.withRequests($._config.resources['kube-rbac-proxy'].requests) +
          container.mixin.resources.withLimits($._config.resources['kube-rbac-proxy'].limits);
  
        local kubeStateMetrics =
          container.new('kube-state-metrics', $._config.imageRepos.kubeStateMetrics + ':' + $._config.versions.kubeStateMetrics) +
          container.withArgs([
            '--host=127.0.0.1',
            '--port=8081',
            '--telemetry-host=127.0.0.1',
            '--telemetry-port=8082',
            '--metric-blacklist=kube_pod_container_status_.*terminated_reason,kube_.+_version,kube_.+_created,kube_deployment_(spec_paused|spec_strategy_rollingupdate_.+),kube_endpoint_(info|address_.+),kube_job_(info|owner|spec_(parallelism|active_deadline_seconds)|status_.+),kube_cronjob_(info|status_.+|spec_.+),kube_namespace_(status_phase),kube_persistentvolume_(info|capacity_.+),kube_persistentvolumeclaim_(resource_.+|access_.+),kube_secret_(type),kube_service_(spec_.+|status_.+),kube_ingress_(info|path|tls),kube_replicaset_(status_.+|spec_.+|owner),kube_poddisruptionbudget_status_.+,kube_replicationcontroller_.+,kube_node_(info|role),kube_(hpa|replicaset|replicationcontroller)_.+_generation',
          ] + if $._config.kubeStateMetrics.collectors != '' then ['--collectors=' + $._config.kubeStateMetrics.collectors] else []) +
          container.mixin.resources.withRequests({ cpu: $._config.kubeStateMetrics.baseCPU, memory: $._config.kubeStateMetrics.baseMemory }) +
          container.mixin.resources.withLimits({});
  
        local c = [proxyClusterMetrics, proxySelfMetrics, kubeStateMetrics];
  
        deployment.new('kube-state-metrics', 1, c, podLabels) +
        deployment.mixin.metadata.withNamespace($._config.namespace) +
        deployment.mixin.metadata.withLabels(podLabels) +
        deployment.mixin.spec.selector.withMatchLabels(podLabels) +
        deployment.mixin.spec.template.spec.withNodeSelector({ 'kubernetes.io/os': 'linux' }) +
        deployment.mixin.spec.template.spec.securityContext.withRunAsNonRoot(true) +
        deployment.mixin.spec.template.spec.securityContext.withRunAsUser(65534) +
        deployment.mixin.spec.template.spec.withServiceAccountName('kube-state-metrics'),

      serviceMonitor+:
        {
          spec+: {
            endpoints: [
              {
                port: 'https-main',
                scheme: 'https',
                interval: $._config.kubeStateMetrics.scrapeInterval,
                scrapeTimeout: $._config.kubeStateMetrics.scrapeTimeout,
                honorLabels: true,
                bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
                relabelings: [
                  {
                    regex: '(service|endpoint)',
                    action: 'labeldrop',
                  },
                ],
                tlsConfig: {
                  insecureSkipVerify: true,
                },
              },
              {
                port: 'https-self',
                scheme: 'https',
                interval: '1m',
                bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
                tlsConfig: {
                  insecureSkipVerify: true,
                },
              },
            ],            
          },
        },      
    }, 

    nodeExporter+:: {
      clusterRoleBinding:
        local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
  
        clusterRoleBinding.new() +
        clusterRoleBinding.mixin.metadata.withName($._config.nodeExporter.name) +
        clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
        clusterRoleBinding.mixin.roleRef.withName('node-exporter') +
        clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
        clusterRoleBinding.withSubjects([{ kind: 'ServiceAccount', name: 'node-exporter', namespace: $._config.namespace }]),
      serviceMonitor+:
        {
          spec+: {
            endpoints: [
              {
                port: 'https',
                scheme: 'https',
                interval: '1m',
                bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
                relabelings: [
                  {
                    regex: '(service|endpoint)',
                    action: 'labeldrop',
                  },
                  {
                    action: 'replace',
                    regex: '(.*)',
                    replacement: '$1',
                    sourceLabels: ['__meta_kubernetes_pod_node_name'],
                    targetLabel: 'instance',
                  },
                ],
                tlsConfig: {
                  insecureSkipVerify: true,
                },
                metricRelabelings: [
                  {
                    sourceLabels: ['__name__'],
                    regex: 'node_cpu_.+|node_memory_Mem.+_bytes|node_memory_SReclaimable_bytes|node_memory_Cached_bytes|node_memory_Buffers_bytes|node_network_(.+_bytes_total|up)|node_disk_.+_completed_total|node_disk_.+_bytes_total|node_filesystem_files|node_filesystem_files_free|node_filesystem_avail_bytes|node_filesystem_size_bytes|node_filesystem_free_bytes|node_load.+|node_timex_offset_seconds',
                    action: 'keep',
                  },
                ],
              },
            ],
          },
        },      
    }, 

    prometheusOperator+:: {
      clusterRoleBinding:
        local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
  
        clusterRoleBinding.new() +
        clusterRoleBinding.mixin.metadata.withLabels($._config.prometheusOperator.commonLabels) +
        clusterRoleBinding.mixin.metadata.withName($._config.prometheusOperator.name) +
        clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
        clusterRoleBinding.mixin.roleRef.withName('prometheus-operator') +
        clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
        clusterRoleBinding.withSubjects([{ kind: 'ServiceAccount', name: 'prometheus-operator', namespace: $._config.namespace }]),
    },

    prometheus+:: {
      serviceKubeScheduler:
        local service = k.core.v1.service;
        local servicePort = k.core.v1.service.mixin.spec.portsType;
  
        local kubeSchedulerServicePort = servicePort.newNamed('http-metrics', 10251, 10251);
  
        service.new('kube-scheduler-svc', null, kubeSchedulerServicePort) +
        service.mixin.metadata.withNamespace('kube-system') +
        service.mixin.metadata.withLabels({ 'k8s-app': 'kube-scheduler' }) +
        service.mixin.spec.withClusterIp('None') +
        service.mixin.spec.withSelector({ 'component': 'kube-scheduler' }),
      serviceKubeControllerManager:
        local service = k.core.v1.service;
        local servicePort = k.core.v1.service.mixin.spec.portsType;
  
        local kubeControllerManagerServicePort = servicePort.newNamed('http-metrics', 10252, 10252);
  
        service.new('kube-controller-manager-svc', null, kubeControllerManagerServicePort) +
        service.mixin.metadata.withNamespace('kube-system') +
        service.mixin.metadata.withLabels({ 'k8s-app': 'kube-controller-manager' }) +
        service.mixin.spec.withClusterIp('None') +
        service.mixin.spec.withSelector({ 'component': 'kube-controller-manager' }),
      roleSpecificNamespaces:
        {
        },
      roleBindingSpecificNamespaces:
        {
        },
      clusterRole:
        local clusterRole = k.rbac.v1.clusterRole;
        local policyRule = clusterRole.rulesType;
  
        local nodeMetricsRule = policyRule.new() +
                                policyRule.withApiGroups(['']) +
                                policyRule.withResources([
                                  'nodes/metrics',
                                  'nodes',
                                  'services',
                                  'endpoints',
                                  'pods',
                                ]) +
                                policyRule.withVerbs(['get', 'list', 'watch']);
  
        local metricsRule = policyRule.new() +
                            policyRule.withNonResourceUrls('/metrics') +
                            policyRule.withVerbs(['get']);
  
        local rules = [nodeMetricsRule, metricsRule];
  
        clusterRole.new() +
        clusterRole.mixin.metadata.withName('prometheus-' + self.name) +
        clusterRole.withRules(rules),
      clusterRoleBinding:
        local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
  
        clusterRoleBinding.new() +
        clusterRoleBinding.mixin.metadata.withName($._config.prometheus.namePrefix + 'prometheus-' + self.name) +
        clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
        clusterRoleBinding.mixin.roleRef.withName('prometheus-' + self.name) +
        clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
        clusterRoleBinding.withSubjects([{ kind: 'ServiceAccount', name: 'prometheus-' + $._config.prometheus.name, namespace: $._config.namespace }]),
      prometheus+:
        local statefulSet = k.apps.v1.statefulSet;
        local toleration = statefulSet.mixin.spec.template.spec.tolerationsType;
        local withTolerations() = {
          tolerations: [
            toleration.new() + (
            if std.objectHas(t, 'key') then toleration.withKey(t.key) else toleration) + (
            if std.objectHas(t, 'operator') then toleration.withOperator(t.operator) else toleration) + (
            if std.objectHas(t, 'value') then toleration.withValue(t.value) else toleration) + (
            if std.objectHas(t, 'effect') then toleration.withEffect(t.effect) else toleration),
            for t in $._config.prometheus.tolerations
          ],
        };
        {
          spec+: {
            retention: $._config.prometheus.retention,
            scrapeInterval: $._config.prometheus.scrapeInterval,
            storage: $._config.prometheus.storage,
            query: $._config.prometheus.query,
            //secrets: ['kube-etcd-client-certs'],
            serviceMonitorSelector: $._config.prometheus.serviceMonitorSelector,
            securityContext: {
              runAsUser: 0,
              runAsNonRoot: false,
              fsGroup: 0,
            },
            additionalScrapeConfigs: {
              name: 'additional-scrape-configs',
              key: 'prometheus-additional.yaml',
            },
          } + withTolerations(),
        },
      serviceMonitor+:
        {
          spec+: {
            endpoints: [
              {
                port: 'web',
                interval: '1m',
                relabelings: [
                  {
                    regex: '(service|endpoint)',
                    action: 'labeldrop',
                  },
                ],
              },
            ],
          },
        },
//      serviceMonitorEtcd+:
//        {
//          metadata+: {
//            namespace: 'kubesphere-monitoring-system',
//          },
//          spec+: {
//            endpoints: [
//              {
//                port: 'metrics',
//                interval: '1m',
//                scheme: 'https',
//                // Prometheus Operator (and Prometheus) allow us to specify a tlsConfig. This is required as most likely your etcd metrics end points is secure.
//                tlsConfig: {
//                  caFile: '/etc/prometheus/secrets/kube-etcd-client-certs/etcd-client-ca.crt',
//                  keyFile: '/etc/prometheus/secrets/kube-etcd-client-certs/etcd-client.key',
//                  certFile: '/etc/prometheus/secrets/kube-etcd-client-certs/etcd-client.crt',
//                  [if $._config.etcd.serverName != null then 'serverName']: $._config.etcd.serverName,
//                  [if $._config.etcd.insecureSkipVerify != null then 'insecureSkipVerify']: $._config.etcd.insecureSkipVerify,
//                },
//              },
//            ],
//          },
//        },
//      secretEtcdCerts: 
//        {
//
//        },
      serviceMonitorKubeScheduler+:
        {
          spec+: {
           endpoints: [
              {
                port: 'http-metrics',
                interval: '1m',
              },
            ],
          },
        },
      serviceMonitorKubelet+:
        {
          spec+: {
            endpoints: [
              {
                port: 'https-metrics',
                scheme: 'https',
                interval: '1m',
                honorLabels: true,
                tlsConfig: {
                  insecureSkipVerify: true,
                },
                bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
                relabelings: [
                  {
                    regex: '(service|endpoint)',
                    action: 'labeldrop',
                  },
                ],
                metricRelabelings: [
                  // Drop unused metrics
                  {
                    sourceLabels: ['__name__'],
                    regex: 'kubelet_node_name|kubelet_running_container_count|kubelet_running_pod_count|kubelet_volume_stats.*',
                    action: 'keep',
                  },
                ],
              },
              {
                port: 'https-metrics',
                scheme: 'https',
                path: '/metrics/cadvisor',
                interval: '1m',
                honorLabels: true,
                tlsConfig: {
                  insecureSkipVerify: true,
                },
                bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
                relabelings: [
                  {
                    regex: '(service|endpoint)',
                    action: 'labeldrop',
                  },
                ],
                metricRelabelings: [
                  {
                    sourceLabels: ['__name__'],
                    regex: 'container_cpu_usage_seconds_total|container_memory_usage_bytes|container_memory_cache|container_network_.+_bytes_total|container_memory_working_set_bytes|container_cpu_cfs_.*periods_total',
                    action: 'keep',
                  },
                ],
              },
            ],
          },
        },
      serviceMonitorKubeControllerManager+:
        {
          spec+: {
            endpoints: [
              {
                port: 'http-metrics',
                interval: '1m',
                metricRelabelings: [
                  {
                    sourceLabels: ['__name__'],
                    regex: 'up',
                    action: 'keep'
                  },
                ],
              },
            ],
          },
        },
      serviceMonitorApiserver+:
        {
          spec+: {
            endpoints: [
              {
                port: 'https',
                interval: '1m',
                scheme: 'https',
                tlsConfig: {
                  caFile: '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt',
                  serverName: 'kubernetes',
                },
                bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
                metricRelabelings: [
                  {
                    sourceLabels: ['__name__'],
                    regex: 'etcd_(debugging|disk|request|server).*',
                    action: 'drop',
                  },
                  {
                    sourceLabels: ['__name__'],
                    regex: 'apiserver_admission_controller_admission_latencies_seconds_.*',
                    action: 'drop',
                  },
                  {
                    sourceLabels: ['__name__'],
                    regex: 'apiserver_admission_step_admission_latencies_seconds_.*',
                    action: 'drop',
                  },
                ],
              },
            ],
          },
        },
      serviceMonitorCoreDNS+:
        {
          spec+: {
            selector+: {
              matchLabels+: {
                'k8s-app': 'coredns',
              },
            },
            endpoints: [
              {
                port: 'metrics',
                interval: '1m',
                bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
              },
            ],
          },
        },    
      serviceMonitorS2IOperator+:
        {
          apiVersion: 'monitoring.coreos.com/v1',
          kind: 'ServiceMonitor',
          metadata: {
            name: 's2i-operator',
            namespace: $._config.namespace,
            labels: {
              'k8s-app': 's2i-operator',
            },
          },
          spec: {
            jobLabel: 'k8s-app',
            selector: {
              matchLabels: {
                'control-plane': 's2i-controller-manager',
                'app': 's2i-metrics',
              },
            },
            namespaceSelector: {
              matchNames: [
                'kubesphere-devops-system',
              ],
            },
            endpoints: [
              {
                port: 'http',
                interval: '1m',
                honorLabels: true,
                metricRelabelings: [
                  {
                    sourceLabels: ['__name__'],
                    regex: 's2i_s2ibuilder_created',
                    action: 'keep',
                  },
                ],
              },
            ],
          },
        },
      }, 
    prometheusAdapter+:: {
      clusterRoleBinding:
        local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
  
        clusterRoleBinding.new() +
        clusterRoleBinding.mixin.metadata.withName($._config.prometheusAdapter.namePrefix + $._config.prometheusAdapter.name) +
        clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
        clusterRoleBinding.mixin.roleRef.withName($.prometheusAdapter.clusterRole.metadata.name) +
        clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
        clusterRoleBinding.withSubjects([{
          kind: 'ServiceAccount',
          name: $.prometheusAdapter.serviceAccount.metadata.name,
          namespace: $._config.namespace,
        }]),
      clusterRoleBindingDelegator:
        local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
  
        clusterRoleBinding.new() +
        clusterRoleBinding.mixin.metadata.withName($._config.prometheusAdapter.namePrefix + 'resource-metrics:system:auth-delegator') +
        clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
        clusterRoleBinding.mixin.roleRef.withName('system:auth-delegator') +
        clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
        clusterRoleBinding.withSubjects([{
          kind: 'ServiceAccount',
          name: $.prometheusAdapter.serviceAccount.metadata.name,
          namespace: $._config.namespace,
        }]),
      roleBindingAuthReader:
        local roleBinding = k.rbac.v1.roleBinding;
  
        roleBinding.new() +
        roleBinding.mixin.metadata.withName($._config.prometheusAdapter.namePrefix + 'resource-metrics-auth-reader') +
        roleBinding.mixin.metadata.withNamespace('kube-system') +
        roleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
        roleBinding.mixin.roleRef.withName('extension-apiserver-authentication-reader') +
        roleBinding.mixin.roleRef.mixinInstance({ kind: 'Role' }) +
        roleBinding.withSubjects([{
          kind: 'ServiceAccount',
          name: $.prometheusAdapter.serviceAccount.metadata.name,
          namespace: $._config.namespace,
        }]),
      customMetricsApiService:
        {
          apiVersion: 'apiregistration.k8s.io/v1',
          kind: 'APIService',
          metadata: {
            name: 'v1beta1.custom.metrics.k8s.io',
          },
          spec: {
            service: {
              name: $.prometheusAdapter.service.metadata.name,
              namespace: $._config.namespace,
            },
            group: 'custom.metrics.k8s.io',
            version: 'v1beta1',
            insecureSkipTLSVerify: true,
            groupPriorityMinimum: 100,
            versionPriority: 100,
          },
        },
      customMetricsClusterRole:
        local clusterRole = k.rbac.v1.clusterRole;
        local policyRule = clusterRole.rulesType;
        local rules =
          policyRule.new() +
          policyRule.withApiGroups(['custom.metrics.k8s.io']) +
          policyRule.withResources(['*']) +
          policyRule.withVerbs(['*']);
        clusterRole.new() +
        clusterRole.mixin.metadata.withName($._config.prometheusAdapter.customMetricsClusterRole) +
        clusterRole.withRules(rules),
      customMetricsClusterRoleBinding:
        local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
        clusterRoleBinding.new() +
        clusterRoleBinding.mixin.metadata.withName($._config.prometheusAdapter.namePrefix + $._config.prometheusAdapter.customMetricsClusterRole) +
        clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
        clusterRoleBinding.mixin.roleRef.withName($._config.prometheusAdapter.customMetricsClusterRole) +
        clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
        clusterRoleBinding.withSubjects([{
          kind: 'ServiceAccount',
          name: $.prometheusAdapter.serviceAccount.metadata.name,
          namespace: $._config.namespace,
        }]),
      hpaCustomMetricsClusterRoleBinding:
        local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
        clusterRoleBinding.new() +
        clusterRoleBinding.mixin.metadata.withName($._config.prometheusAdapter.namePrefix + $._config.prometheusAdapter.hpaCustomMetricsClusterRole) +
        clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
        clusterRoleBinding.mixin.roleRef.withName($._config.prometheusAdapter.customMetricsClusterRole) +
        clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
        clusterRoleBinding.withSubjects([{
          kind: 'ServiceAccount',
          name: $._config.prometheusAdapter.hpaServiceAccount,
          namespace: $._config.prometheusAdapter.hpaNameSpace,
        }]),
      },
  };

local manifests =
  // Uncomment line below to enable vertical auto scaling of kube-state-metrics
  // { ['ksm-autoscaler-' + name]: kp.ksmAutoscaler[name] for name in std.objectFields(kp.ksmAutoscaler) } +
  { ['setup/0namespace-' + name]: kp.kubePrometheus[name] for name in std.objectFields(kp.kubePrometheus) } +
  {
    ['setup/prometheus-operator-' + name]: kp.prometheusOperator[name]
    for name in std.filter((function(name) name != 'serviceMonitor'), std.objectFields(kp.prometheusOperator))
  } +
  // serviceMonitor is separated so that it can be created after the CRDs are ready
  { 'prometheus-operator-serviceMonitor': kp.prometheusOperator.serviceMonitor } +
  { ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
  { ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
  { ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
  { ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } +
  { ['prometheus-adapter-' + name]: kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter) } +
  { ['grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) };

local kustomizationResourceFile(name) = './manifests/' + name + '.yaml';
local kustomization = {
  apiVersion: 'kustomize.config.k8s.io/v1beta1',
  kind: 'Kustomization',
  resources: std.map(kustomizationResourceFile, std.objectFields(manifests)),
};

manifests {
  '../kustomization': kustomization,
}
