package com.cloudcostguardian;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import software.amazon.awssdk.services.autoscaling.model.AutoScalingGroup;
import software.amazon.awssdk.services.autoscaling.model.DescribeAutoScalingGroupsRequest;
import software.amazon.awssdk.services.autoscaling.model.DescribeAutoScalingGroupsResponse;
import software.amazon.awssdk.services.autoscaling.model.UpdateAutoScalingGroupRequest;
import software.amazon.awssdk.services.ec2.model.DescribeInstancesRequest;
import software.amazon.awssdk.services.ec2.model.DescribeInstancesResponse;
import software.amazon.awssdk.services.ec2.model.Filter;
import software.amazon.awssdk.services.ec2.model.Instance;
import software.amazon.awssdk.services.ec2.model.Reservation;
import software.amazon.awssdk.services.ec2.model.StopInstancesRequest;
import software.amazon.awssdk.services.ec2.model.TerminateInstancesRequest;

import java.util.HashMap;
import java.util.Map;

public class Handler implements RequestHandler<Map<String, Object>, Map<String, Object>> {
    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        Settings settings = Settings.fromEnvironment(System.getenv());
        AwsClients clients = new AwsClients(settings.region);
        AuditLogger audit = new AuditLogger(clients, settings.auditTableName);
        Notifier notifier = new Notifier(clients, settings.snsTopicArn);

        int ec2Scanned = 0;
        int ec2Flagged = 0;
        int ec2Actions = 0;
        int asgScanned = 0;
        int asgFlagged = 0;
        int asgActions = 0;

        DescribeInstancesResponse ec2Response = clients.ec2.describeInstances(DescribeInstancesRequest.builder()
                .filters(Filter.builder().name("instance-state-name").values("running").build())
                .build());

        for (Reservation reservation : ec2Response.reservations()) {
            for (Instance instance : reservation.instances()) {
                ec2Scanned++;
                CloudWatchUtilization.IdleResult idleResult = CloudWatchUtilization.isIdle(clients, instance.instanceId(), settings);
                EvaluationResult result = PolicyEngine.evaluateEc2(instance, settings, idleResult.idle);

                if (!result.compliant) {
                    ec2Flagged++;
                }

                audit.write(result.resourceId, result.resourceType, result.resourceName, "SCAN", result.reason, result.environment, result.owner,
                        result.compliant ? "SCANNED" : "FLAGGED_NON_COMPLIANT", result.details);

                if (result.shouldNotify) {
                    notifier.notify(result, "WARN");
                }

                if (result.shouldAct) {
                    if (settings.performActions) {
                        if ("STOP".equals(result.action)) {
                            clients.ec2.stopInstances(StopInstancesRequest.builder().instanceIds(result.resourceId).build());
                        } else if ("TERMINATE".equals(result.action)) {
                            clients.ec2.terminateInstances(TerminateInstancesRequest.builder().instanceIds(result.resourceId).build());
                        }
                        audit.write(result.resourceId, result.resourceType, result.resourceName, result.action, result.reason, result.environment, result.owner,
                                "SUCCESS", "Remediation applied.");
                        notifier.notify(result, "ACTION");
                        ec2Actions++;
                    } else {
                        audit.write(result.resourceId, result.resourceType, result.resourceName, result.action, result.reason, result.environment, result.owner,
                                "SKIPPED_DRY_RUN", "PERFORM_ACTIONS is false.");
                    }
                }
            }
        }

        DescribeAutoScalingGroupsResponse asgResponse = clients.asg.describeAutoScalingGroups(DescribeAutoScalingGroupsRequest.builder().build());
        for (AutoScalingGroup asg : asgResponse.autoScalingGroups()) {
            asgScanned++;
            EvaluationResult result = PolicyEngine.evaluateAsg(asg, settings);

            if (!result.compliant) {
                asgFlagged++;
            }

            audit.write(result.resourceId, result.resourceType, result.resourceName, "SCAN", result.reason, result.environment, result.owner,
                    result.compliant ? "SCANNED" : "FLAGGED_NON_COMPLIANT", result.details);

            if (result.shouldNotify) {
                notifier.notify(result, "WARN");
            }

            if (result.shouldAct && "SCALE_TO_ZERO".equals(result.action)) {
                if (settings.performActions) {
                    UpdateAutoScalingGroupRequest.Builder update = UpdateAutoScalingGroupRequest.builder()
                            .autoScalingGroupName(result.resourceId)
                            .desiredCapacity(0);
                    if (settings.setAsgMinToZero) {
                        update.minSize(0);
                    }
                    clients.asg.updateAutoScalingGroup(update.build());
                    audit.write(result.resourceId, result.resourceType, result.resourceName, result.action, result.reason, result.environment, result.owner,
                            "SUCCESS", "ASG scaled to zero.");
                    notifier.notify(result, "ACTION");
                    asgActions++;
                } else {
                    audit.write(result.resourceId, result.resourceType, result.resourceName, result.action, result.reason, result.environment, result.owner,
                            "SKIPPED_DRY_RUN", "PERFORM_ACTIONS is false.");
                }
            }
        }

        Map<String, Object> summary = new HashMap<>();
        summary.put("ec2_scanned", ec2Scanned);
        summary.put("ec2_flagged", ec2Flagged);
        summary.put("ec2_actions", ec2Actions);
        summary.put("asg_scanned", asgScanned);
        summary.put("asg_flagged", asgFlagged);
        summary.put("asg_actions", asgActions);

        Map<String, Object> output = new HashMap<>();
        output.put("statusCode", 200);
        output.put("summary", summary);
        return output;
    }
}
