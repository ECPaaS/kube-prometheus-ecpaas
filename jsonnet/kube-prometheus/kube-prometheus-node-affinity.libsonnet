local k = import 'ksonnet/ksonnet.beta.4/k.libsonnet';

local statefulSet = k.apps.v1.statefulSet;
local nodeAffinity = statefulSet.mixin.spec.template.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecutionType;
local matchExpression = nodeAffinity.mixin.preference.matchExpressionsType;
local nodeAffinityRequired = k.apps.v1.daemonSet.mixin.spec.template.spec.affinity.nodeAffinity;

{
  local affinity(key) = {
    affinity+: {
      nodeAffinity: {
        preferredDuringSchedulingIgnoredDuringExecution: [
          nodeAffinity.new() + 
          nodeAffinity.withWeight(100) +
          nodeAffinity.mixin.preference.withMatchExpressions([
            matchExpression.new() +
            matchExpression.withKey(key) +
            matchExpression.withOperator('Exists'), 
          ]),
        ],
      },
    },
  },

  local affinityRequired(key, operator) = {
    template+: {
      spec+:{
        affinity+: {
          nodeAffinity: {
            requiredDuringSchedulingIgnoredDuringExecution: {
              nodeSelectorTerms: [
                nodeAffinityRequired.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTermsType.withMatchExpressions([
                  matchExpression.new() +
                  matchExpression.withKey(key) +
                  matchExpression.withOperator(operator),
                ]),
              ],
            },
          },
        },
      },
    },
  },

  prometheus+: {
    prometheus+: {
      spec+:
        affinity('node-role.kubernetes.io/monitoring'),
    },
  },

  nodeExporter+: {
    daemonset+: {
      spec+:
        affinityRequired('node-role.kubernetes.io/edge', 'DoesNotExist'),
    },
  },
}