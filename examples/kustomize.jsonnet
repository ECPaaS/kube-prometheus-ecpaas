local k = import 'ksonnet/ksonnet.beta.4/k.libsonnet';
local kp =
  (import 'kube-prometheus/kube-prometheus.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-anti-affinity.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-static-etcd.libsonnet') +
  (import 'kube-prometheus/kube-prometheus-strip-limits.libsonnet')
  {
    _config+:: {
      namespace: 'kubesphere-monitoring-system',

      versions+:: {
        prometheus: "v2.11.0",
        alertmanager: "v0.18.0",
        kubeStateMetrics: "v1.5.2", // v1.7.2
        kubeRbacProxy: "v0.4.1",
        addonResizer: "1.8.4",
        nodeExporter: "ks-v0.16.0", // v0.18.1
        prometheusOperator: 'v0.33.0',
        configmapReloader: 'v0.0.1',
        prometheusConfigReloader: 'v0.33.0',
        prometheusAdapter: 'v0.4.1',
        thanos: "v0.7.0",
        clusterVerticalAutoscaler: "1.0.0"
      },

      imageRepos+:: {
        prometheus: "dockerhub.qingcloud.com/prometheus/prometheus",
        alertmanager: "dockerhub.qingcloud.com/prometheus/alertmanager",
        kubeStateMetrics: "dockerhub.qingcloud.com/coreos/kube-state-metrics",
        kubeRbacProxy: "dockerhub.qingcloud.com/coreos/kube-rbac-proxy",
        addonResizer: "dockerhub.qingcloud.com/coreos/addon-resizer",
        nodeExporter: "dockerhub.qingcloud.com/prometheus/node-exporter",
        prometheusOperator: "dockerhub.qingcloud.com/coreos/prometheus-operator",
        configmapReloader: 'dockerhub.qingcloud.com/coreos/configmap-reload',
        prometheusConfigReloader: 'dockerhub.qingcloud.com/coreos/prometheus-config-reloader',
        prometheusAdapter: 'dockerhub.qingcloud.com/coreos/k8s-prometheus-adapter-amd64',
        thanos: 'dockerhub.qingcloud.com/thanos/thanos',
        clusterVerticalAutoscaler: 'gcr.io/google_containers/cluster-proportional-vertical-autoscaler-amd64'
      },

      prometheus+:: {
        retention: '7d',
        scrapeInterval: '1m',
        namespaces: ['default', 'kube-system', 'istio-system', $._config.namespace],
        serviceMonitorSelector: {matchExpressions: [{key: 'k8s-app', operator: 'In', values: ['kube-state-metrics', 'node-exporter', 'kubelet', 'prometheus', 'etcd', 'coredns', 'apiserver', 'kube-scheduler', 'kube-controller-manager']}]},
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
        ]
      },

      kubeStateMetrics+:: {
        scrapeInterval: '1m',
      },

      etcd+:: {
        ips: ['127.0.0.1'],
        clientCA: importstr 'etcd-client-ca.crt',
        clientKey: importstr 'etcd-client.key',
        clientCert: importstr 'etcd-client.crt',
        serverName: 'etcd.kube-system.svc.cluster.local',
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
                metricRelabelings: [
                  // Drop unused metrics
                  {
                    sourceLabels: ['__name__'],
                    regex: 'kube_pod_container_status_.*terminated_reason',
                    action: 'drop',
                  },
                ],
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
                    regex: 'node_cpu_.+|node_memory_Mem.+_bytes|node_memory_Cached_bytes|node_memory_Buffers_bytes|node_network_.+_bytes_total|node_disk_.+_completed_total|node_disk_.+_bytes_total|node_filesystem_files|node_filesystem_files_free|node_filesystem_avail_bytes|node_filesystem_size_bytes|node_filesystem_free_bytes|node_load.+',
                    action: 'keep',
                  },
                ],
              },
            ],
          },
        },      
    }, 

    prometheus+:: {
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
            secrets: ['kube-etcd-client-certs'],
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
          },
        },
      secretEtcdCerts: 
        {

        },
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
                metricRelabelings: [
                  // Drop unused metrics
                  {
                    sourceLabels: ['__name__'],
                    regex: 'kubelet_running_container_count|kubelet_running_pod_count|kubelet_volume_stats.*',
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
                metricRelabelings: [
                  {
                    sourceLabels: ['__name__'],
                    regex: 'container_cpu_usage_seconds_total|container_memory_usage_bytes|container_memory_cache|container_network_.+_bytes_total|container_memory_working_set_bytes',
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
      }, 
  };

local manifests =
  { ['00namespace-' + name]: kp.kubePrometheus[name] for name in std.objectFields(kp.kubePrometheus) } +
  { ['0prometheus-operator-' + name]: kp.prometheusOperator[name] for name in std.objectFields(kp.prometheusOperator) } +
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
