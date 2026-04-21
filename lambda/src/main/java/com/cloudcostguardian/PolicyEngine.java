package com.cloudcostguardian;

import software.amazon.awssdk.services.autoscaling.model.AutoScalingGroup;
import software.amazon.awssdk.services.autoscaling.model.TagDescription;
import software.amazon.awssdk.services.ec2.model.Instance;
import software.amazon.awssdk.services.ec2.model.Tag;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeParseException;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

public final class PolicyEngine {
    private PolicyEngine() {
    }

    public static EvaluationResult evaluateEc2(Instance instance, Settings settings, boolean idle) {
        Map<String, String> tags = toEc2TagMap(instance);
        String id = instance.instanceId();
        String name = tags.getOrDefault("Name", id);
        String owner = tags.getOrDefault("Owner", "unknown");
        String env = tags.getOrDefault("Environment", "unknown").toLowerCase(Locale.ROOT);

        if (!hasRequiredTags(tags, settings)) {
            return new EvaluationResult("EC2", id, name, env, owner, false, true, false, "NONE", "MISSING_REQUIRED_TAGS", "Resource missing required tags.");
        }
        if ("prod".equals(env)) {
            return new EvaluationResult("EC2", id, name, env, owner, true, false, false, "NONE", "PRODUCTION_SKIPPED", "Production resource is skipped.");
        }
        if (isProtected(tags)) {
            return new EvaluationResult("EC2", id, name, env, owner, true, false, false, "NONE", "PROTECTED_BY_TAG", "KeepAlive or DoNotDelete is enabled.");
        }

        Instant ttl = parseTtl(tags.get("TTL"));
        if (ttl != null && !ttl.isAfter(Instant.now())) {
            String action = settings.autoTerminateEnvs.contains(env) ? "TERMINATE" : "STOP";
            boolean shouldAct = settings.autoStopEnvs.contains(env);
            return new EvaluationResult("EC2", id, name, env, owner, true, true, shouldAct, action, "TTL_EXPIRED", "TTL has expired.");
        }

        if (idle && settings.autoStopEnvs.contains(env)) {
            return new EvaluationResult("EC2", id, name, env, owner, true, true, true, "STOP", "IDLE_THRESHOLD_BREACH", "CPU and network are below idle threshold.");
        }

        return new EvaluationResult("EC2", id, name, env, owner, true, false, false, "NONE", "NO_ACTION", "No action required.");
    }

    public static EvaluationResult evaluateAsg(AutoScalingGroup asg, Settings settings) {
        Map<String, String> tags = toAsgTagMap(asg);
        String id = asg.autoScalingGroupName();
        String owner = tags.getOrDefault("Owner", "unknown");
        String env = tags.getOrDefault("Environment", "unknown").toLowerCase(Locale.ROOT);

        if (!hasRequiredTags(tags, settings)) {
            return new EvaluationResult("ASG", id, id, env, owner, false, true, false, "NONE", "MISSING_REQUIRED_TAGS", "ASG missing required tags.");
        }
        if ("prod".equals(env)) {
            return new EvaluationResult("ASG", id, id, env, owner, true, false, false, "NONE", "PRODUCTION_SKIPPED", "Production ASG is skipped.");
        }
        if (isProtected(tags)) {
            return new EvaluationResult("ASG", id, id, env, owner, true, false, false, "NONE", "PROTECTED_BY_TAG", "KeepAlive or DoNotDelete is enabled.");
        }

        Instant ttl = parseTtl(tags.get("TTL"));
        if (ttl != null && !ttl.isAfter(Instant.now()) && settings.autoStopEnvs.contains(env)) {
            return new EvaluationResult("ASG", id, id, env, owner, true, true, true, "SCALE_TO_ZERO", "TTL_EXPIRED", "ASG TTL has expired.");
        }

        return new EvaluationResult("ASG", id, id, env, owner, true, false, false, "NONE", "NO_ACTION", "No action required.");
    }

    private static Map<String, String> toEc2TagMap(Instance instance) {
        Map<String, String> tags = new HashMap<>();
        for (Tag tag : instance.tags()) {
            tags.put(tag.key(), tag.value());
        }
        return tags;
    }

    private static Map<String, String> toAsgTagMap(AutoScalingGroup asg) {
        Map<String, String> tags = new HashMap<>();
        for (TagDescription tag : asg.tags()) {
            tags.put(tag.key(), tag.value());
        }
        return tags;
    }

    private static boolean hasRequiredTags(Map<String, String> tags, Settings settings) {
        for (String required : settings.requiredTags) {
            String value = tags.get(required);
            if (value == null || value.isBlank()) {
                return false;
            }
        }
        return true;
    }

    private static boolean isProtected(Map<String, String> tags) {
        return isTruthy(tags.getOrDefault("KeepAlive", "false")) || isTruthy(tags.getOrDefault("DoNotDelete", "false"));
    }

    private static boolean isTruthy(String value) {
        String normalized = value.trim().toLowerCase(Locale.ROOT);
        return normalized.equals("1") || normalized.equals("true") || normalized.equals("yes") || normalized.equals("on");
    }

    private static Instant parseTtl(String ttl) {
        if (ttl == null || ttl.isBlank()) {
            return null;
        }
        try {
            return Instant.parse(ttl);
        } catch (DateTimeParseException ignored) {
            try {
                return OffsetDateTime.parse(ttl).withOffsetSameInstant(ZoneOffset.UTC).toInstant();
            } catch (DateTimeParseException ignoredAgain) {
                return null;
            }
        }
    }
}
