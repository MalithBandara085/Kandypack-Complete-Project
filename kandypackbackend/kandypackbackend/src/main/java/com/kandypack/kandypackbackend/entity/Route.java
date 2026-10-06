package com.kandypack.kandypackbackend.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;

@Entity
@Table(name = "route")
public class Route {

    @Id
    @Column(name = "route_id")
    private String routeId;

    @ManyToOne
    @JoinColumn(name = "store_id", nullable = false)
    private Store store;

    @Column(name = "city", nullable = false)
    private String city;

    @Column(name = "coverage_area", nullable = false)
    private String coverageArea;

    @Column(name = "max_delivery_time", nullable = false)
    private BigDecimal maxDeliveryTime;

    public String getRouteId() { return routeId; }
    public void setRouteId(String routeId) { this.routeId = routeId; }

    public Store getStore() { return store; }
    public void setStore(Store store) { this.store = store; }

    public String getCity() { return city; }
    public void setCity(String city) { this.city = city; }

    public String getCoverageArea() { return coverageArea; }
    public void setCoverageArea(String coverageArea) { this.coverageArea = coverageArea; }

    public BigDecimal getMaxDeliveryTime() { return maxDeliveryTime; }
    public void setMaxDeliveryTime(BigDecimal maxDeliveryTime) { this.maxDeliveryTime = maxDeliveryTime; }
}