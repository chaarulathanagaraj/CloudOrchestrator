package com.cloudcostguardian;

import software.amazon.awssdk.services.sns.model.MessageAttributeValue;
import software.amazon.awssdk.services.sns.model.PublishRequest;

import java.util.HashMap;
import java.util.Map;

public final class Notifier {
    private final AwsClients clients;
    private final String topicArn;

    public Notifier(AwsClients clients, String topicArn) {
        this.clients = clients;
        this.topicArn = topicArn;
    }

    public void notify(EvaluationResult result, String phase) {
        if (topicArn == null || topicArn.isBlank()) {
            return;
        }

        String subject = String.format("[CloudCostGuard][%s] %s %s: %s", phase, result.resourceType, result.resourceId, result.reason);
        String message = String.format(
                "resource_type=%s\nresource_id=%s\nresource_name=%s\nenvironment=%s\nowner=%s\naction=%s\nreason=%s\ndetails=%s",
                result.resourceType,
                result.resourceId,
                result.resourceName,
                result.environment,
                result.owner,
                result.action,
                result.reason,
                result.details
        );

        Map<String, MessageAttributeValue> attributes = new HashMap<>();
        attributes.put("resourceType", MessageAttributeValue.builder().dataType("String").stringValue(result.resourceType).build());
        attributes.put("reason", MessageAttributeValue.builder().dataType("String").stringValue(result.reason).build());
        attributes.put("environment", MessageAttributeValue.builder().dataType("String").stringValue(result.environment).build());

        clients.sns.publish(PublishRequest.builder()
                .topicArn(topicArn)
                .subject(subject.substring(0, Math.min(subject.length(), 100)))
                .message(message)
                .messageAttributes(attributes)
                .build());
    }
}
