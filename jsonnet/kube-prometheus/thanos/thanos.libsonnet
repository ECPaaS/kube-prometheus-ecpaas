local k3 = import 'ksonnet/ksonnet.beta.3/k.libsonnet';
local k = import 'ksonnet/ksonnet.beta.4/k.libsonnet';

{
  _config+:: {
    namespace: 'default',

    labels+:: {
      rulerLabels: { 'thanos-ruler': 'kubesphere' },
    },

    thanos+:: {
      thanosRuler: 'thanos-ruler',
      thanosRulerName: 'kubesphere',
    },
  },

  thanos+:: {
    local po = self,
    namespace:: $._config.namespace,
    image:: $._config.imageRepos.thanos,
    version:: $._config.versions.thanos,
    rulerLabels:: $._config.labels.rulerLabels,
    name:: $._config.thanos.thanosRulerName,
    ruler:
      {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'ThanosRuler',
        metadata: {
          labels: po.rulerLabels,
          name: po.name,
          namespace: po.namespace,
        },
        spec: {
          image: po.image + ':' + po.version,
          resources: {
            limits: {
              cpu: '500m',
              memory: '500Mi',
            },
            requests: {
              cpu: '100m',
              memory: '100Mi',
            },
          },
          replicas: 1,
          ruleNamespaceSelector: {},
          ruleSelector: {
            matchLabels: {
              role: 'thanos-alerting-rules',
              thanosruler: 'thanos-ruler',
            },
          },
          alertmanagersUrl: ['dnssrv+http://alertmanager-operated.kubesphere-monitoring-system.svc:9093'],
          queryEndpoints: ['prometheus-operated.kubesphere-monitoring-system.svc:9090'],
        },
      },
  },
}