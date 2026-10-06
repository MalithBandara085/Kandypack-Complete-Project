package com.kandypack.kandypackbackend.entity;

import jakarta.persistence.Embeddable;
import java.io.Serializable;
import java.util.Objects;

@Embeddable
public class OrderTravelId implements Serializable {

    private String orderId;
    private String tripId;

    public OrderTravelId() {}

    public OrderTravelId(String orderId, String tripId) {
        this.orderId = orderId;
        this.tripId = tripId;
    }

    public String getOrderId() { return orderId; }
    public void setOrderId(String orderId) { this.orderId = orderId; }

    public String getTripId() { return tripId; }
    public void setTripId(String tripId) { this.tripId = tripId; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof OrderTravelId)) return false;
        OrderTravelId that = (OrderTravelId) o;
        return Objects.equals(orderId, that.orderId) && Objects.equals(tripId, that.tripId);
    }

    @Override
    public int hashCode() {
        return Objects.hash(orderId, tripId);
    }
}