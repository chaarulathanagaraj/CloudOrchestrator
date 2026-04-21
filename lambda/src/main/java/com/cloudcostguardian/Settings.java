package com.cloudcostguardian;

import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

public final class Settings {
    public final String region;
    public final String snsTopicArn;
    public final String auditTableName;
    public final List<String> autoStopEnvs;
    public final List<String> autoTerminateEnvs;
    public final List<String> requiredTags;
    public final double idleCpuMax;
    public final double idleNetworkBytesMax;
    public final int idleLookbackHours;
    public final boolean performActions;
    public final boolean setAsgMinToZero;

    private Settings(
            String region,
            String snsTopicArn,
            String auditTableName,
            List<String> autoStopEnvs,
            List<String> autoTerminateEnvs,
            List<String> requiredTags,
            double idleCpuMax,
            double idleNetworkBytesMax,
            int idleLookbackHours,
            boolean performActions,
            boolean setAsgMinToZero
    ) {
        this.region = region;
        this.snsTopicArn = snsTopicArn;
        this.auditTableName = auditTableName;
        this.autoStopEnvs = autoStopEnvs;
        this.autoTerminateEnvs = autoTerminateEnvs;
        this.requiredTags = requiredTags;
        this.idleCpuMax = idleCpuMax;
        this.idleNetworkBytesMax = idleNetworkBytesMax;
        this.idleLookbackHours = idleLookbackHours;
        this.performActions = performActions;
        this.setAsgMinToZero = setAsgMinToZero;
    }

    public static Settings fromEnvironment(Map<String, String> env) {
        return new Settings(
                envOrDefault(env, "AWS_REGION", "us-east-1"),
                envOrDefault(env, "SNS_TOPIC_ARN", ""),
                envOrDefault(env, "AUDIT_TABLE_NAME", "resource_audit_log"),
                listOrDefault(env, "AUTO_STOP_ENVS", List.of("dev", "test", "sandbox")),
                listOrDefault(env, "AUTO_TERMINATE_ENVS", List.of("sandbox")),
                listOrDefault(env, "REQUIRED_TAGS", List.of("Owner", "Environment", "TTL")),
                doubleOrDefault(env, "IDLE_CPU_MAX", 5.0),
                doubleOrDefault(env, "IDLE_NETWORK_BYTES_MAX", 1048576.0),
                intOrDefault(env, "IDLE_LOOKBACK_HOURS", 6),
                boolOrDefault(env, "PERFORM_ACTIONS", false),
                boolOrDefault(env, "SET_ASG_MIN_TO_ZERO", true)
        );
    }

    private static String envOrDefault(Map<String, String> env, String key, String fallback) {
        String value = env.get(key);
        return value == null || value.isBlank() ? fallback : value;
    }

    private static boolean boolOrDefault(Map<String, String> env, String key, boolean fallback) {
        String value = env.get(key);
        if (value == null) {
            return fallback;
        }
        String normalized = value.trim().toLowerCase();
        return normalized.equals("1") || normalized.equals("true") || normalized.equals("yes") || normalized.equals("on");
    }

    private static int intOrDefault(Map<String, String> env, String key, int fallback) {
        String value = env.get(key);
        if (value == null || value.isBlank()) {
            return fallback;
        }
        return Integer.parseInt(value);
    }

    private static double doubleOrDefault(Map<String, String> env, String key, double fallback) {
        String value = env.get(key);
        if (value == null || value.isBlank()) {
            return fallback;
        }
        return Double.parseDouble(value);
    }

    private static List<String> listOrDefault(Map<String, String> env, String key, List<String> fallback) {
        String value = env.get(key);
        if (value == null || value.isBlank()) {
            return fallback;
        }
        return Arrays.stream(value.split(","))
                .map(String::trim)
                .filter(s -> !s.isBlank())
                .collect(Collectors.toList());
    }
}
