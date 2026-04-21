package com.cloudcostguardian;

public final class EvaluationResult {
    public final String resourceType;
    public final String resourceId;
    public final String resourceName;
    public final String environment;
    public final String owner;
    public final boolean compliant;
    public final boolean shouldNotify;
    public final boolean shouldAct;
    public final String action;
    public final String reason;
    public final String details;

    public EvaluationResult(
            String resourceType,
            String resourceId,
            String resourceName,
            String environment,
            String owner,
            boolean compliant,
            boolean shouldNotify,
            boolean shouldAct,
            String action,
            String reason,
            String details
    ) {
        this.resourceType = resourceType;
        this.resourceId = resourceId;
        this.resourceName = resourceName;
        this.environment = environment;
        this.owner = owner;
        this.compliant = compliant;
        this.shouldNotify = shouldNotify;
        this.shouldAct = shouldAct;
        this.action = action;
        this.reason = reason;
        this.details = details;
    }
}
