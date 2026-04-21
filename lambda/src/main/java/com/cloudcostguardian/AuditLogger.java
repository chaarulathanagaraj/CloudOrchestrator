package com.cloudcostguardian;

import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

public final class AuditLogger {
    private final AwsClients clients;
    private final String tableName;

    public AuditLogger(AwsClients clients, String tableName) {
        this.clients = clients;
        this.tableName = tableName;
    }

    public void write(String resourceId, String resourceType, String resourceName, String action, String reason, String environment, String owner, String outcome, String details) {
        Map<String, AttributeValue> item = new HashMap<>();
        item.put("pk", AttributeValue.builder().s(resourceId).build());
        item.put("sk", AttributeValue.builder().s(Instant.now().toString()).build());
        item.put("resource_type", AttributeValue.builder().s(resourceType).build());
        item.put("resource_name", AttributeValue.builder().s(resourceName == null ? "" : resourceName).build());
        item.put("action", AttributeValue.builder().s(action).build());
        item.put("reason", AttributeValue.builder().s(reason).build());
        item.put("environment", AttributeValue.builder().s(environment).build());
        item.put("owner", AttributeValue.builder().s(owner).build());
        item.put("outcome", AttributeValue.builder().s(outcome).build());
        item.put("details", AttributeValue.builder().s(details).build());

        clients.dynamoDb.putItem(PutItemRequest.builder().tableName(tableName).item(item).build());
    }
}
