package com.cloudcostguardian;

import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.autoscaling.AutoScalingClient;
import software.amazon.awssdk.services.cloudwatch.CloudWatchClient;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.ec2.Ec2Client;
import software.amazon.awssdk.services.sns.SnsClient;

public final class AwsClients {
    public final Ec2Client ec2;
    public final AutoScalingClient asg;
    public final CloudWatchClient cloudWatch;
    public final SnsClient sns;
    public final DynamoDbClient dynamoDb;

    public AwsClients(String regionName) {
        Region region = Region.of(regionName);
        this.ec2 = Ec2Client.builder().region(region).build();
        this.asg = AutoScalingClient.builder().region(region).build();
        this.cloudWatch = CloudWatchClient.builder().region(region).build();
        this.sns = SnsClient.builder().region(region).build();
        this.dynamoDb = DynamoDbClient.builder().region(region).build();
    }
}
