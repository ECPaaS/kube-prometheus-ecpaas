{
  kubeStateMetrics+:: (import 'kube-state-metrics/kube-state-metrics.libsonnet') +
                      {
                        local ksm = self,
                        name:: $._config.kubeStateMetrics.name,
                        namespace:: $._config.namespace,
                        version:: '1.9.4',
                        image:: $._config.imageRepos.kubeStateMetrics + ':v' + ksm.version,
                        local k = import 'ksonnet/ksonnet.beta.4/k.libsonnet',

                        clusterRoleBinding:
                          local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
                      
                          clusterRoleBinding.new() +
                          clusterRoleBinding.mixin.metadata.withName($._config.namePrefix + ksm.name) +
                          clusterRoleBinding.mixin.metadata.withLabels(ksm.commonLabels) +
                          clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
                          clusterRoleBinding.mixin.roleRef.withName(ksm.name) +
                          clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
                          clusterRoleBinding.withSubjects([{ kind: 'ServiceAccount', name: ksm.name, namespace: ksm.namespace }]),

                        deployment:
                          local deployment = k.apps.v1.deployment;
                          local container = deployment.mixin.spec.template.spec.containersType;
                          local volume = deployment.mixin.spec.template.spec.volumesType;
                          local containerPort = container.portsType;
                          local containerVolumeMount = container.volumeMountsType;
                          local podSelector = deployment.mixin.spec.template.spec.selectorType;
                      
                          local c =
                            container.new('kube-state-metrics', ksm.image) +
                            container.withArgs([
                              '--metric-blacklist=kube_pod_container_status_.*terminated_reason,kube_.+_version,kube_.+_created,kube_deployment_(spec_paused|spec_strategy_rollingupdate_.+),kube_endpoint_(info|address_.+),kube_job_(info|owner|spec_(parallelism|active_deadline_seconds)|status_(active|.+_time)),kube_cronjob_(info|status_.+|spec_.+),kube_namespace_(status_phase),kube_persistentvolume_(info|capacity_.+),kube_persistentvolumeclaim_(resource_.+|access_.+),kube_secret_(type),kube_service_(spec_.+|status_.+),kube_ingress_(info|path|tls),kube_replicaset_(status_.+|spec_.+|owner),kube_poddisruptionbudget_status_.+,kube_replicationcontroller_.+,kube_node_(info|role),kube_(hpa|replicaset|replicationcontroller)_.+_generation',
                            ]) +
                            container.withPorts([
                              containerPort.newNamed(8080, 'http-metrics'),
                              containerPort.newNamed(8081, 'telemetry'),
                            ]) +
                            container.mixin.livenessProbe.httpGet.withPath('/healthz') +
                            container.mixin.livenessProbe.httpGet.withPort(8080) +
                            container.mixin.livenessProbe.withInitialDelaySeconds(5) +
                            container.mixin.livenessProbe.withTimeoutSeconds(5) +
                            container.mixin.readinessProbe.httpGet.withPath('/') +
                            container.mixin.readinessProbe.httpGet.withPort(8081) +
                            container.mixin.readinessProbe.withInitialDelaySeconds(5) +
                            container.mixin.readinessProbe.withTimeoutSeconds(5) +
                            container.mixin.securityContext.withRunAsUser(65534);
                      
                          deployment.new(ksm.name, 1, c, ksm.commonLabels) +
                          deployment.mixin.metadata.withNamespace(ksm.namespace) +
                          deployment.mixin.metadata.withLabels(ksm.commonLabels) +
                          deployment.mixin.spec.selector.withMatchLabels(ksm.podLabels) +
                          deployment.mixin.spec.template.spec.withNodeSelector({ 'kubernetes.io/os': 'linux' }) +
                          deployment.mixin.spec.template.spec.withServiceAccountName(ksm.name),
                        serviceMonitor: {
                          apiVersion: 'monitoring.coreos.com/v1',
                          kind: 'ServiceMonitor',
                          metadata: {
                            name: ksm.name,
                            namespace: ksm.namespace,
                            labels: ksm.commonLabels,
                          },
                          spec: {
                            jobLabel: 'app.kubernetes.io/name',
                            selector: {
                              matchLabels: ksm.commonLabels,
                            },
                            endpoints: [
                              {
                                port: 'http-metrics',
                                interval: $._config.kubeStateMetrics.scrapeInterval,
                                scrapeTimeout: $._config.kubeStateMetrics.scrapeTimeout,
                                honorLabels: true,
                                relabelings: [
                                  {
                                    regex: '(service|endpoint)',
                                    action: 'labeldrop',
                                  },
                                ],
                              },
                              {
                                port: 'telemetry',
                                interval: $._config.kubeStateMetrics.scrapeInterval,
                              },
                            ],
                          },
                        },
                      },
}
