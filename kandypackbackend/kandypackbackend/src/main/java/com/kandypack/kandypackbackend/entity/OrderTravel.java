package com.kandypack.kandypackbackend.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "order_travel")
public class OrderTravel {

    @EmbeddedId
    private OrderTravelId id;

    @ManyToOne
    @MapsId("orderId")
    @JoinColumn(name = "order_id")
    private CustomerOrder order;

    @ManyToOne
    @MapsId("tripId")
    @JoinColumn(name = "trip_id")
    private TrainSchedule trip;

    @ManyToOne
    @JoinColumn(name = "route_id", nullable = false)
    private Route route;

    public OrderTravelId getId() { return id; }
    public void setId(OrderTravelId id) { this.id = id; }

    public CustomerOrder getOrder() { return order; }
    public void setOrder(CustomerOrder order) { this.order = order; }

    public TrainSchedule getTrip() { return trip; }
    public void setTrip(TrainSchedule trip) { this.trip = trip; }

    public Route getRoute() { return route; }
    public void setRoute(Route route) { this.route = route; }
}