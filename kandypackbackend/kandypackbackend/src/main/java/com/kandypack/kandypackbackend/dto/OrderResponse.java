package com.kandypack.kandypackbackend.dto;

import com.kandypack.kandypackbackend.entity.CustomerOrder;
import java.math.BigDecimal;
import java.time.LocalDate;

public class OrderResponse {

    private String orderId;
    private String customerId;
    private String customerName;
    private BigDecimal amount;
    private LocalDate placementDate;
    private LocalDate deliveryDate;
    private String status;

    private java.util.List<TrainAllocation> allocations = java.util.List.of();

    public java.util.List<TrainAllocation> getAllocations() { return allocations; }
    public void setAllocations(java.util.List<TrainAllocation> allocations) { this.allocations = allocations; }

    public record TrainAllocation(String tripId, String productId, String productName,
                                  int quantity, BigDecimal reservedSpace, String routeId,
                                  java.time.LocalDateTime departure, java.time.LocalDateTime arrival,
                                  boolean active) {}

    public OrderResponse(CustomerOrder order) {
        this.orderId = order.getOrderId();
        this.customerId = order.getCustomer().getCustomerId();
        this.customerName = order.getCustomer().getCustomerName();
        this.amount = order.getAmount();
        this.placementDate = order.getPlacementDate();
        this.deliveryDate = order.getDeliveryDate();
        this.status = order.getStatus();
    }

    public String getOrderId() { return orderId; }
    public String getCustomerId() { return customerId; }
    public String getCustomerName() { return customerName; }
    public BigDecimal getAmount() { return amount; }
    public LocalDate getPlacementDate() { return placementDate; }
    public LocalDate getDeliveryDate() { return deliveryDate; }
    public String getStatus() { return status; }
}