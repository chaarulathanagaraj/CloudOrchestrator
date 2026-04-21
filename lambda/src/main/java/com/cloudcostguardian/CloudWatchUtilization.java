package com.cloudcostguardian;

import software.amazon.awssdk.services.cloudwatch.model.Datapoint;
import software.amazon.awssdk.services.cloudwatch.model.Dimension;
import software.amazon.awssdk.services.cloudwatch.model.GetMetricStatisticsRequest;
import software.amazon.awssdk.services.cloudwatch.model.GetMetricStatisticsResponse;
import software.amazon.awssdk.services.cloudwatch.model.Statistic;

import java.time.Instant;
import java.util.List;

public final class CloudWatchUtilization {
    private CloudWatchUtilization() {
    }

    public static IdleResult isIdle(AwsClients clients, String instanceId, Settings settings) {
        Instant end = Instant.now();
        Instant start = end.minusSeconds(settings.idleLookbackHours * 3600L);
        List<Dimension> dimensions = List.of(Dimension.builder().name("InstanceId").value(instanceId).build());

        double avgCpu = metricAverage(clients, "AWS/EC2", "CPUUtilization", dimensions, start, end);
        double avgNetIn = metricAverage(clients, "AWS/EC2", "NetworkIn", dimensions, start, end);
        double avgNetOut = metricAverage(clients, "AWS/EC2", "NetworkOut", dimensions, start, end);
        double totalNet = avgNetIn + avgNetOut;

        boolean idle = avgCpu <= settings.idleCpuMax && totalNet <= settings.idleNetworkBytesMax;
        return new IdleResult(idle, avgCpu, avgNetIn, avgNetOut, totalNet);
    }

    private static double metricAverage(
            AwsClients clients,
            String namespace,
            String metricName,
            List<Dimension> dimensions,
            Instant start,
            Instant end
    ) {
        GetMetricStatisticsRequest request = GetMetricStatisticsRequest.builder()
                .namespace(namespace)
                .metricName(metricName)
                .dimensions(dimensions)
                .startTime(start)
                .endTime(end)
                .period(300)
                .statistics(Statistic.AVERAGE)
                .build();
        GetMetricStatisticsResponse response = clients.cloudWatch.getMetricStatistics(request);
        if (response.datapoints().isEmpty()) {
            return 0.0;
        }
        double sum = 0.0;
        for (Datapoint point : response.datapoints()) {
            sum += point.average() == null ? 0.0 : point.average();
        }
        return sum / response.datapoints().size();
    }

    public static final class IdleResult {
        public final boolean idle;
        public final double avgCpu;
        public final double avgNetIn;
        public final double avgNetOut;
        public final double avgNetTotal;

        public IdleResult(boolean idle, double avgCpu, double avgNetIn, double avgNetOut, double avgNetTotal) {
            this.idle = idle;
            this.avgCpu = avgCpu;
            this.avgNetIn = avgNetIn;
            this.avgNetOut = avgNetOut;
            this.avgNetTotal = avgNetTotal;
        }
    }
}
