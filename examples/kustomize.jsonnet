local k = import 'ksonnet/ksonnet.beta.4/k.libsonnet';
local kp =
  (import 'kube-prometheus/kube-prometheus.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-static-etcd.libsonnet') +
//(import 'kube-prometheus/ksm-autoscaler/ksm-autoscaler.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-strip-limits.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-anti-affinity.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-node-affinity.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-thanos-sidecar.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-custom-metrics.libsonnet') +
  {
    _config+:: {
      namespace: 'kubesphere-monitoring-system',
      namePrefix: 'ks-',

      versions+:: {
        prometheus: "v2.17.2",
        alertmanager: "v0.20.0",
        kubeStateMetrics: "1.9.6",
        kubeRbacProxy: "v0.4.1",
        addonResizer: "1.8.4",
        nodeExporter: "ks-v0.18.1", 
        prometheusOperator: 'v0.38.1',
        configmapReloader: 'v0.3.0',
        prometheusConfigReloader: 'v0.38.1',
        prometheusAdapter: 'v0.5.0',
        thanos: "v0.10.0",
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
        configmapReloader: 'jimmidyson/configmap-reload',
        prometheusConfigReloader: 'kubesphere/prometheus-config-reloader',
        prometheusAdapter: 'kubesphere/k8s-prometheus-adapter-amd64',
        thanos: 'kubesphere/thanos',
        clusterVerticalAutoscaler: 'gcr.io/google_containers/cluster-proportional-vertical-autoscaler-amd64'
      },

      prometheus+:: {
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
          inhibit_rules: [{
            source_match: {
              severity: 'critical',
            },
            target_match_re: {
              severity: 'warning|info',
            },
            equal: ['namespace', 'alertname'],
          }, {
            source_match: {
              severity: 'warning',
            },
            target_match_re: {
              severity: 'info',
            },
            equal: ['namespace', 'alertname'],
          }],
          route+: {
            group_by: ['namespace', 'alertname'],
          },
        },
      },

      kubeStateMetrics+:: {
        name: 'kube-state-metrics',
        scrapeInterval: '1m',
        scrapeTimeout: '30s',
      },

      nodeExporter+:: {
        name: 'node-exporter',
      },

      prometheusOperator+:: {
        name: 'prometheus-operator',
      },
      etcd+:: {
        ips: ['127.0.0.1'],
        clientCA: importstr 'etcd-client-ca.crt',
        clientKey: importstr 'etcd-client.key',
        clientCert: importstr 'etcd-client.crt',
        serverName: 'etcd.kube-system.svc.cluster.local',
        rules: $.prometheusEtcdRules + $.prometheusEtcdAlerts,
      },
      prometheusAdapter+:: {
        config+: {
          resourceRules: {
            cpu: {
              containerQuery: 'sum(irate(container_cpu_usage_seconds_total{<<.LabelMatchers>>,container!="POD",container!="",pod!=""}[5m])) by (<<.GroupBy>>)',
              nodeQuery: 'sum(irate(node_cpu_seconds_total{mode="used"}[5m]) * on(namespace, pod) group_left(node) node_namespace_pod:kube_pod_info:{<<.LabelMatchers>>}) by (<<.GroupBy>>)',
              resources: {
                overrides: {
                  node: {
                    resource: 'node'
                  },
                  namespace: {
                    resource: 'namespace'
                  },
                  pod: {
                    resource: 'pod'
                  },
                },
              },
              containerLabel: 'container'
            },
            memory: {
              containerQuery: 'sum(container_memory_working_set_bytes{<<.LabelMatchers>>,container!="POD",container!="",pod!=""}) by (<<.GroupBy>>)',
              nodeQuery: 'sum(node_memory_MemTotal_bytes{job="node-exporter",<<.LabelMatchers>>} - node_memory_MemFree_bytes{job="node-exporter",<<.LabelMatchers>>} - node_memory_Cached_bytes{job="node-exporter",<<.LabelMatchers>>} - node_memory_Buffers_bytes{job="node-exporter",<<.LabelMatchers>>} - node_memory_SReclaimable_bytes{job="node-exporter",<<.LabelMatchers>>}) by (<<.GroupBy>>)',
              resources: {
                overrides: {
                  instance: {
                    resource: 'node'
                  },
                  namespace: {
                    resource: 'namespace'
                  },
                  pod: {
                    resource: 'pod'
                  },
                },
              },
              containerLabel: 'container'
            },
            window: '5m',
          },
        }
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

    kubeStateMetrics+:: {
      serviceMonitor+:
        {
          spec+:{
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
                interval: $._config.kubeStateMetrics.scrapeInterval,
                bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
                tlsConfig: {
                  insecureSkipVerify: true,
                },
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

    nodeExporter+:: {
      clusterRoleBinding:
        local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
  
        clusterRoleBinding.new() +
        clusterRoleBinding.mixin.metadata.withName($._config.namePrefix + $._config.nodeExporter.name) +
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
        clusterRoleBinding.mixin.metadata.withName($._config.namePrefix + $._config.prometheusOperator.name) +
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
        clusterRoleBinding.mixin.metadata.withName($._config.namePrefix + 'prometheus-' + self.name) +
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
      serviceMonitorEtcd+:
        {
          metadata+: {
            namespace: 'kubesphere-monitoring-system',
          },
          spec+: {
            endpoints: [
              {
                port: 'metrics',
                interval: '1m',
                scheme: 'https',
                // Prometheus Operator (and Prometheus) allow us to specify a tlsConfig. This is required as most likely your etcd metrics end points is secure.
                tlsConfig: {
                  caFile: '/etc/prometheus/secrets/kube-etcd-client-certs/etcd-client-ca.crt',
                  keyFile: '/etc/prometheus/secrets/kube-etcd-client-certs/etcd-client.key',
                  certFile: '/etc/prometheus/secrets/kube-etcd-client-certs/etcd-client.crt',
                  [if $._config.etcd.serverName != null then 'serverName']: $._config.etcd.serverName,
                  [if $._config.etcd.insecureSkipVerify != null then 'insecureSkipVerify']: $._config.etcd.insecureSkipVerify,
                },
              },
            ],
            namespaceSelector: {
              matchNames: [
                'kube-system',
              ],
            },
          },
        },
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
                metricRelabelings: [
                  {
                    sourceLabels: ['__name__'],
                    regex: 'scheduler_(e2e_scheduling_latency_microseconds|scheduling_algorithm_predicate_evaluation|scheduling_algorithm_priority_evaluation|scheduling_algorithm_preemption_evaluation|scheduling_algorithm_latency_microseconds|binding_latency_microseconds|scheduling_latency_seconds)',
                    action: 'drop',
                  },
                ],
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
                    regex: 'kubelet_node_name|kubelet_running_container_count|kubelet_running_pod_count|kubelet_volume_stats.*|kubelet_pleg_relist_duration_seconds_.+',
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
                metricRelabelings: (import 'kube-prometheus/dropping-deprecated-metrics-relabelings.libsonnet') + [
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
                  {
                    sourceLabels: ['__name__', 'le'],
                    regex: 'apiserver_request_duration_seconds_bucket;(0.15|0.25|0.3|0.35|0.4|0.45|0.6|0.7|0.8|0.9|1.25|1.5|1.75|2.5|3|3.5|4.5|6|7|8|9|15|25|30|50)',
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
      rulesEtcd:
        {
          apiVersion: 'monitoring.coreos.com/v1',
          kind: 'PrometheusRule',
          metadata: {
            labels: {
              prometheus: $._config.prometheus.name,
              role: 'alert-rules',
            },
            name: 'prometheus-' + $._config.prometheus.name + '-etcd-rules',
            namespace: $._config.namespace,
          },
          spec: {
            groups: $._config.etcd.rules.groups,
          },
        },
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
