{
  _config+:: {
    versions+:: {
      kubeStateMetrics: '1.9.5',
    },
    imageRepos+:: {
      kubeStateMetrics: 'quay.io/coreos/kube-state-metrics',
    },
    kubeStateMetrics+:: {
      scrapeInterval: '30s',
      scrapeTimeout: '30s',
    },
  },
  kubeStateMetrics+:: (import 'kube-state-metrics/kube-state-metrics.libsonnet') +
                      {
                        local ksm = self,
                        name:: 'kube-state-metrics',
                        namespace:: $._config.namespace,
                        version:: $._config.versions.kubeStateMetrics,
                        image:: $._config.imageRepos.kubeStateMetrics + ':v' + $._config.versions.kubeStateMetrics,
                        service+: {
                          spec+: {
                            ports: [
                              {
                                name: 'https-main',
                                port: 8443,
                                targetPort: 'https-main',
                              },
                              {
                                name: 'https-self',
                                port: 9443,
                                targetPort: 'https-self',
                              },
                            ],
                          },
                        },
                        deployment+: {
                          spec+: {
                            template+: {
                              spec+: {
                                containers: std.map(function(c) c {
                                  ports:: null,
                                  livenessProbe:: null,
                                  readinessProbe:: null,
                                  args: ['--host=127.0.0.1', '--port=8081', '--telemetry-host=127.0.0.1', '--telemetry-port=8082', '--metric-denylist=kube_pod_container_status_.*terminated_reason,kube_.+_version,kube_.+_created,kube_deployment_(spec_paused|spec_strategy_rollingupdate_.+),kube_endpoint_(info|address_.+),kube_job_(info|owner|spec_(parallelism|active_deadline_seconds)|status_(active|.+_time)),kube_cronjob_(info|status_.+|spec_.+),kube_namespace_(status_phase),kube_persistentvolume_(info|capacity_.+),kube_persistentvolumeclaim_(resource_.+|access_.+),kube_secret_(type),kube_service_(spec_.+|status_.+),kube_ingress_(info|path|tls),kube_replicaset_(status_.+|spec_.+|owner),kube_poddisruptionbudget_status_.+,kube_replicationcontroller_.+,kube_node_(info|role),kube_(hpa|replicaset|replicationcontroller)_.+_generation'],
                                }, super.containers),
                              },
                            },
                          },
                        },
                        serviceMonitor:
                          {
                            apiVersion: 'monitoring.coreos.com/v1',
                            kind: 'ServiceMonitor',
                            metadata: {
                              name: 'kube-state-metrics',
                              namespace: $._config.namespace,
                              labels: {
                                'app.kubernetes.io/name': 'kube-state-metrics',
                                'app.kubernetes.io/version': ksm.version,
                              },
                            },
                            spec: {
                              jobLabel: 'app.kubernetes.io/name',
                              selector: {
                                matchLabels: {
                                  'app.kubernetes.io/name': 'kube-state-metrics',
                                },
                              },
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
                                      regex: '(pod|service|endpoint|namespace)',
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
                      } +
                      ((import 'kube-prometheus/kube-rbac-proxy/container.libsonnet') {
                         config+:: {
                           kubeRbacProxy: {
                             local cfg = self,
                             image: $._config.imageRepos.kubeRbacProxy + ':' + $._config.versions.kubeRbacProxy,
                             name: 'kube-rbac-proxy-main',
                             securePortName: 'https-main',
                             securePort: 8443,
                             secureListenAddress: ':%d' % self.securePort,
                             upstream: 'http://127.0.0.1:8081/',
                             tlsCipherSuites: $._config.tlsCipherSuites,
                           },
                         },
                       }).deploymentMixin +
                      ((import 'kube-prometheus/kube-rbac-proxy/container.libsonnet') {
                         config+:: {
                           kubeRbacProxy: {
                             local cfg = self,
                             image: $._config.imageRepos.kubeRbacProxy + ':' + $._config.versions.kubeRbacProxy,
                             name: 'kube-rbac-proxy-self',
                             securePortName: 'https-self',
                             securePort: 9443,
                             secureListenAddress: ':%d' % self.securePort,
                             upstream: 'http://127.0.0.1:8082/',
                             tlsCipherSuites: $._config.tlsCipherSuites,
                           },
                         },
                       }).deploymentMixin,
}